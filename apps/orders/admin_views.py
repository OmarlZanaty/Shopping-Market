"""
Admin endpoints under /api/v1/admin/orders/.
"""
from decimal import Decimal
from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from django.db.models import Count, Q
from django.utils import timezone
from django.contrib.auth import get_user_model

from .models import Order, OrderItem, OrderAdjustment
from .serializers import (
    OrderSerializer, OrderListSerializer, AssignSerializer, CancelOrderSerializer,
)
from .services import cancel_order, OrderError
from apps.core.permissions import IsAdminWriteOrSupportRead
from apps.core.scoping import scope_to_user
from apps.core.responses import ok, fail
from apps.notifications.utils import send_push_notification
from apps.users.models import WalletTransaction

User = get_user_model()


def _lookup_admin_order(order_id, user):
    qs = scope_to_user(Order.objects.all(), user, scope_field='store_id', branch_field='branch_id')
    return (qs.filter(order_number=order_id).first()
            or qs.filter(order_id=order_id).first()
            or qs.filter(id=order_id).first())


class AdminOrderListView(generics.ListAPIView):
    serializer_class = OrderListSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    filterset_fields = ['status', 'payment_method', 'branch', 'store']
    search_fields = ['order_number', 'order_id', 'customer__full_name', 'customer__phone']
    ordering_fields = ['created_at', 'total_amount', 'status']

    def get_queryset(self):
        qs = (Order.objects
              .select_related('customer', 'driver', 'preparer', 'branch', 'store')
              .prefetch_related('items'))
        qs = scope_to_user(qs, self.request.user, branch_field='branch_id')
        from_date = self.request.query_params.get('from_date')
        to_date = self.request.query_params.get('to_date')
        if from_date:
            qs = qs.filter(created_at__date__gte=from_date)
        if to_date:
            qs = qs.filter(created_at__date__lte=to_date)
        return qs.order_by('-created_at')


class AdminOrderDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get(self, request, order_id):
        order = _lookup_admin_order(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        return ok(OrderSerializer(order, context={'request': request}).data)


class AdminAssignPreparerView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request, order_id):
        ser = AssignSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        preparer_id = ser.validated_data.get('preparer_id')
        if not preparer_id:
            return fail('preparer_id required', status_code=400)
        order = _lookup_admin_order(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        try:
            preparer = User.objects.get(pk=preparer_id, role='preparer', is_active=True)
        except User.DoesNotExist:
            return fail('Preparer not found or not active', status_code=404)
        if preparer.store_id and preparer.store_id != order.store_id:
            return fail('Preparer is not in this store', status_code=400)
        order.preparer = preparer
        if not order.accepted_at:
            order.accepted_at = timezone.now()
        order.save(update_fields=['preparer', 'accepted_at'])
        send_push_notification(
            user=preparer,
            title_ar='طلب جديد!', title_en='New Order Assigned',
            body_ar=f'تم تعيينك لطلب {order.order_number}',
            body_en=f'You have been assigned order {order.order_number}',
            data={'type': 'new_order', 'order_id': str(order.id),
                  'order_number': order.order_number},
        )
        return ok({'preparer_assigned': preparer.full_name})


class AdminAssignDriverView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request, order_id):
        ser = AssignSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        driver_id = ser.validated_data.get('driver_id')
        if not driver_id:
            return fail('driver_id required', status_code=400)
        order = _lookup_admin_order(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        try:
            driver = User.objects.get(pk=driver_id, role='driver', is_active=True)
        except User.DoesNotExist:
            return fail('Driver not found or not active', status_code=404)
        if driver.store_id and driver.store_id != order.store_id:
            return fail('Driver is not in this store', status_code=400)
        order.driver = driver
        order.save(update_fields=['driver'])
        send_push_notification(
            user=driver,
            title_ar='طلب جديد!', title_en='New Delivery Assigned',
            body_ar=f'تم تعيينك لطلب {order.order_number}',
            body_en=f'You have been assigned order {order.order_number}',
            data={'type': 'new_order', 'order_id': str(order.id),
                  'order_number': order.order_number},
        )
        return ok({'driver_assigned': driver.full_name})


class AdminCancelOrderView(APIView):
    """Admin cancel with mandatory reason. Process refund. Notify customer."""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request, order_id):
        ser = CancelOrderSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        reason = (ser.validated_data.get('reason') or '').strip()
        if not reason:
            return fail('Cancellation reason is required', status_code=400)
        order = _lookup_admin_order(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        # Admin can cancel even out_for_delivery (spec says reason mandatory)
        if order.status == Order.Status.DELIVERED:
            return fail('Cannot cancel a delivered order — use return endpoint', status_code=400)
        if order.status == Order.Status.CANCELLED:
            return fail('Already cancelled', status_code=400)

        # Force the cancel through services (handles refund + restock)
        try:
            order.status = Order.Status.NEW  # bypass status check inside cancel_order
            cancel_order(order, by_user=request.user, reason=reason)
        except OrderError as e:
            return fail(str(e), status_code=400)
        return ok({'cancelled': True, 'reason': reason})


class AdminReturnOrderView(APIView):
    """
    POST /admin/orders/:id/return
    Body: { items: [{item_id, qty, condition}], refund_method: 'wallet'|'cash' }
    Issues refund proportional to refunded items.
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def post(self, request, order_id):
        order = _lookup_admin_order(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.DELIVERED:
            return fail('Returns only allowed on delivered orders', status_code=400)
        items_data = request.data.get('items') or []
        if not isinstance(items_data, list) or not items_data:
            return fail('items list required', status_code=400)
        refund_method = request.data.get('refund_method', 'wallet')
        refund_total = Decimal('0')
        for it in items_data:
            try:
                item = order.items.get(pk=it['item_id'])
                qty = Decimal(str(it['qty']))
            except (OrderItem.DoesNotExist, KeyError, ValueError, TypeError):
                continue
            refund_total += Decimal(str(item.unit_price)) * qty
            OrderAdjustment.objects.create(
                order=order, order_item=item,
                preparer=None, driver=None,
                action_type=OrderAdjustment.AdjustmentType.ITEM_REMOVED,
                old_value=str(item.quantity), new_value=str(qty),
                reason=f"return — condition: {it.get('condition', 'n/a')}",
            )
        if refund_total <= 0:
            return fail('No valid items to refund', status_code=400)
        # Issue refund
        if refund_method == 'wallet':
            order.customer.wallet_balance = float(order.customer.wallet_balance) + float(refund_total)
            order.customer.save(update_fields=['wallet_balance'])
            WalletTransaction.objects.create(
                user=order.customer,
                type=WalletTransaction.Type.CREDIT,
                amount=refund_total,
                reason=WalletTransaction.Reason.REFUND,
                balance_after=order.customer.wallet_balance,
                reference_id=str(order.id),
                reference_type='order_return',
            )
        order.payment_status = Order.PaymentStatus.PARTIAL
        order.save(update_fields=['payment_status'])
        send_push_notification(
            user=order.customer,
            title_ar='تم استرداد مبلغ', title_en='Refund issued',
            body_ar=f'{refund_total} جنيه استردت إلى محفظتك',
            body_en=f'EGP {refund_total} refunded to your wallet',
            data={'type': 'general', 'amount': str(refund_total), 'order_id': str(order.id)},
        )
        return ok({'refunded': str(refund_total), 'method': refund_method})


class AdminOrdersLiveView(APIView):
    """Real-time counts per status for dashboard cards."""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get(self, request):
        qs = scope_to_user(Order.objects.all(), request.user, branch_field='branch_id')
        counts = qs.values('status').annotate(count=Count('id'))
        result = {row['status']: row['count'] for row in counts}
        return ok({
            'new': result.get('new', 0),
            'accepted': result.get('accepted', 0),
            'preparing': result.get('preparing', 0),
            'out_for_delivery': result.get('out_for_delivery', 0),
            'delivered_today': qs.filter(
                status='delivered',
                delivered_at__date=timezone.now().date(),
            ).count(),
            'cancelled_today': qs.filter(
                status='cancelled',
                cancelled_at__date=timezone.now().date(),
            ).count(),
        })


class AdminTrackingDriversView(APIView):
    """GET /admin/tracking/drivers — proxy to users.AdminDriversLiveView."""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get(self, request):
        from apps.users.views import AdminDriversLiveView
        return AdminDriversLiveView().get(request)
