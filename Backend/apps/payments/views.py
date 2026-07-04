"""
Payment endpoints:
  POST /payments/adjustment-topup/     — Initiate card payment for a price increase
  POST /payments/webhook/paymob/       — Paymob HMAC-validated webhook
"""
import hashlib
import hmac
import json
import logging

from django.conf import settings
from django.db import transaction
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from rest_framework import permissions
from rest_framework.views import APIView

from apps.core.responses import ok, fail
from apps.orders.models import Order, OrderAdjustment
from .models import PaymobTransaction
from .paymob import create_payment, PaymobError

logger = logging.getLogger(__name__)


class InitiateAdjustmentPaymentView(APIView):
    """
    POST /payments/adjustment-topup/
    Body: { order_id, adjustment_id }

    The customer already approved a price-increase adjustment. This endpoint
    creates a Paymob payment for the DIFFERENCE between the new total and the
    original total and returns the iframe URL to embed in a WebView.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        order_id = request.data.get('order_id')
        adjustment_id = request.data.get('adjustment_id')

        if not order_id or not adjustment_id:
            return fail('order_id and adjustment_id are required', status_code=400)

        # Fetch order — must belong to this customer
        try:
            order = Order.objects.get(id=order_id, customer=request.user)
        except Order.DoesNotExist:
            return fail('Order not found', status_code=404)

        # Fetch adjustment — must be approved and price_change type
        try:
            adj = OrderAdjustment.objects.get(
                pk=adjustment_id,
                order=order,
                action_type='price_change',
                customer_approval_status='approved',
            )
        except OrderAdjustment.DoesNotExist:
            return fail('Adjustment not found or not approved', status_code=404)

        # Calculate the extra amount owed
        try:
            new_total = float(adj.new_total or order.total_amount)
            old_total = float(adj.old_value or 0)
            diff = round(new_total - old_total, 2)
        except (TypeError, ValueError):
            diff = float(order.total_amount)

        if diff <= 0:
            return fail('No additional payment required', status_code=400)

        # Check for existing pending transaction (idempotency)
        existing = PaymobTransaction.objects.filter(
            order=order, adjustment=adj, status=PaymobTransaction.Status.PENDING
        ).first()
        if existing and existing.paymob_payment_key:
            return ok({
                'iframe_url': (
                    f'https://accept.paymob.com/api/acceptance/iframes/'
                    f'{settings.PAYMOB_IFRAME_ID}?payment_token={existing.paymob_payment_key}'
                ),
                'transaction_id': existing.id,
                'amount_egp': str(existing.amount_egp),
            })

        # Create Paymob payment
        try:
            merchant_order_id = f'adj-{adj.id}-{order.order_number}'
            result = create_payment(
                amount_egp=diff,
                merchant_order_id=merchant_order_id,
                customer_name=request.user.full_name or 'Customer',
                customer_phone=str(request.user.phone or ''),
                customer_email=getattr(request.user, 'email', '') or 'NA',
            )
        except PaymobError as e:
            logger.error('Paymob initiation failed for adj %s: %s', adjustment_id, e)
            return fail('فشل في إنشاء رابط الدفع — حاول مرة أخرى', status_code=502)

        # Persist transaction record
        tx = PaymobTransaction.objects.create(
            order=order,
            adjustment=adj,
            customer=request.user,
            transaction_type=PaymobTransaction.TransactionType.ADJUSTMENT_TOP_UP,
            amount_egp=diff,
            amount_cents=int(round(diff * 100)),
            paymob_order_id=result['paymob_order_id'],
            paymob_payment_key=result['payment_key'],
        )

        return ok({
            'iframe_url': result['iframe_url'],
            'transaction_id': tx.id,
            'amount_egp': str(diff),
        })


@method_decorator(csrf_exempt, name='dispatch')
class PaymobWebhookView(APIView):
    """
    POST /payments/webhook/paymob/
    Called by Paymob on transaction completion. Validates HMAC, then marks
    the PaymobTransaction and the Order payment_status as paid.
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request):
        # ── HMAC validation ───────────────────────────────────────────────────
        hmac_secret = getattr(settings, 'PAYMOB_HMAC_SECRET', '')
        incoming_hmac = request.query_params.get('hmac', '')
        if hmac_secret and not self._verify_hmac(request.data, incoming_hmac, hmac_secret):
            logger.warning('Paymob webhook: invalid HMAC')
            return fail('Invalid HMAC', status_code=400)

        obj = request.data.get('obj', {})
        success = obj.get('success', False)
        paymob_tx_id = str(obj.get('id', ''))
        paymob_order = obj.get('order', {})
        merchant_order_id = str(paymob_order.get('merchant_order_id', ''))

        if not success or not paymob_tx_id:
            # Payment failed or cancelled — update transaction to failed
            self._mark_failed(merchant_order_id, paymob_tx_id)
            return ok({'received': True})

        # ── Mark as paid ──────────────────────────────────────────────────────
        try:
            with transaction.atomic():
                # Locate our transaction record
                tx = None
                if merchant_order_id:
                    # merchant_order_id format: 'adj-{adj_id}-{order_number}'
                    tx = PaymobTransaction.objects.filter(
                        paymob_order_id=str(paymob_order.get('id', ''))
                    ).first()
                if tx is None and paymob_tx_id:
                    tx = PaymobTransaction.objects.filter(
                        paymob_transaction_id=paymob_tx_id
                    ).first()

                if tx is None:
                    logger.warning('Paymob webhook: no matching transaction for %s', merchant_order_id)
                    return ok({'received': True})

                tx.status = PaymobTransaction.Status.PAID
                tx.paymob_transaction_id = paymob_tx_id
                tx.webhook_data = request.data
                tx.save(update_fields=['status', 'paymob_transaction_id', 'webhook_data', 'updated_at'])

                # Update the order payment status
                order = tx.order
                order.payment_status = Order.PaymentStatus.PAID
                order.paymob_order_id = tx.paymob_order_id
                order.save(update_fields=['payment_status', 'paymob_order_id', 'updated_at'])

                # Notify customer
                try:
                    from apps.notifications.utils import send_push_notification
                    send_push_notification(
                        user=order.customer,
                        title_ar='تم الدفع بنجاح ✅',
                        title_en='Payment successful',
                        body_ar=f'تم تأكيد دفعك لطلب رقم {order.order_number}',
                        body_en=f'Payment confirmed for order #{order.order_number}',
                        data={'type': 'payment_confirmed', 'order_id': str(order.id),
                              'order_number': order.order_number},
                    )
                except Exception:
                    pass

        except Exception as e:
            logger.exception('Paymob webhook processing error: %s', e)
            return fail('Internal error', status_code=500)

        return ok({'received': True})

    @staticmethod
    def _verify_hmac(data: dict, incoming: str, secret: str) -> bool:
        """
        Paymob HMAC is computed over a specific set of fields in alphabetical
        order, concatenated without separator.
        """
        fields = [
            'amount_cents', 'created_at', 'currency', 'error_occured',
            'has_parent_transaction', 'id', 'integration_id',
            'is_3d_secure', 'is_auth', 'is_capture', 'is_refunded',
            'is_standalone_payment', 'is_voided', 'order', 'owner',
            'pending', 'source_data.pan', 'source_data.sub_type',
            'source_data.type', 'success',
        ]
        obj = data.get('obj', {})
        src = obj.get('source_data', {})
        resolved = {
            'amount_cents': obj.get('amount_cents', ''),
            'created_at': obj.get('created_at', ''),
            'currency': obj.get('currency', ''),
            'error_occured': str(obj.get('error_occured', '')).lower(),
            'has_parent_transaction': str(obj.get('has_parent_transaction', '')).lower(),
            'id': obj.get('id', ''),
            'integration_id': obj.get('integration_id', ''),
            'is_3d_secure': str(obj.get('is_3d_secure', '')).lower(),
            'is_auth': str(obj.get('is_auth', '')).lower(),
            'is_capture': str(obj.get('is_capture', '')).lower(),
            'is_refunded': str(obj.get('is_refunded', '')).lower(),
            'is_standalone_payment': str(obj.get('is_standalone_payment', '')).lower(),
            'is_voided': str(obj.get('is_voided', '')).lower(),
            'order': str(obj.get('order', {}).get('id', '')),
            'owner': str(obj.get('owner', '')),
            'pending': str(obj.get('pending', '')).lower(),
            'source_data.pan': src.get('pan', ''),
            'source_data.sub_type': src.get('sub_type', ''),
            'source_data.type': src.get('type', ''),
            'success': str(obj.get('success', '')).lower(),
        }
        concatenated = ''.join(str(resolved.get(f, '')) for f in fields)
        expected = hmac.new(secret.encode(), concatenated.encode(), hashlib.sha512).hexdigest()
        return hmac.compare_digest(expected, incoming)

    @staticmethod
    def _mark_failed(merchant_order_id: str, paymob_tx_id: str):
        try:
            tx = PaymobTransaction.objects.filter(
                paymob_order_id__contains=merchant_order_id,
                status=PaymobTransaction.Status.PENDING,
            ).first()
            if tx:
                tx.status = PaymobTransaction.Status.FAILED
                tx.paymob_transaction_id = paymob_tx_id
                tx.save(update_fields=['status', 'paymob_transaction_id', 'updated_at'])
        except Exception:
            pass
