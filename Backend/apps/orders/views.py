"""
Customer-facing order endpoints. Agent + admin endpoints live in agent_views.py
and admin_views.py respectively.
"""
from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from django.utils import timezone
from django.db import transaction

from .models import Order, OrderItem, OrderAdjustment, OrderRating, SmartTimerAutoClose
from .serializers import (
    OrderSerializer, OrderCreateSerializer, OrderListSerializer,
    OrderItemSerializer, OrderAdjustmentSerializer, OrderRatingSerializer,
    AdjustPriceSerializer, AdjustQuantitySerializer, SubstituteItemSerializer,
    AddItemSerializer, CancelOrderSerializer, ApproveAdjustmentSerializer,
)
from .services import create_customer_order, cancel_order, OrderError
from apps.products.models import Product
from apps.core.responses import ok, fail
from apps.core.permissions import IsCustomer


# ─── Customer-facing ─────────────────────────────────────────────────────────

class CustomerOrderListView(generics.ListAPIView):
    serializer_class = OrderListSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Order.objects.filter(customer=self.request.user)
            .select_related('driver', 'preparer', 'branch', 'store')
            .order_by('-created_at')
        )


class CustomerCreateOrderView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        ser = OrderCreateSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        try:
            order = create_customer_order(request.user, ser.validated_data)
        except OrderError as e:
            return fail(str(e), status_code=400)
        return ok(OrderSerializer(order, context={'request': request}).data,
                  message='Order created', status_code=status.HTTP_201_CREATED)


class CustomerOrderDetailView(generics.RetrieveAPIView):
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        # Look up by order_number (legacy: order_id) OR primary key (UUID)
        identifier = self.kwargs['order_id']
        qs = Order.objects.filter(customer=self.request.user)
        order = qs.filter(order_number=identifier).first() or qs.filter(order_id=identifier).first()
        if not order:
            order = qs.filter(id=identifier).first()
        if not order:
            from django.http import Http404
            raise Http404('Order not found')
        return order


class CustomerCancelOrderView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, order_id):
        ser = CancelOrderSerializer(data=request.data)
        ser.is_valid()
        reason = ser.validated_data.get('reason', '')

        qs = Order.objects.filter(customer=request.user)
        order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
                 or qs.filter(id=order_id).first())
        if not order:
            return fail('Order not found', status_code=404)
        try:
            cancel_order(order, by_user=request.user, reason=reason)
        except OrderError as e:
            return fail(str(e), status_code=400)
        return ok(OrderSerializer(order, context={'request': request}).data,
                  message='Order cancelled')


class CustomerConfirmReceiptView(APIView):
    """Customer confirms delivery received. Awards loyalty points."""
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, order_id):
        return self._confirm(request, order_id)

    def post(self, request, order_id):  # back-compat
        return self._confirm(request, order_id)

    def _confirm(self, request, order_id):
        qs = Order.objects.filter(customer=request.user)
        order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
                 or qs.filter(id=order_id).first())
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.OUT_FOR_DELIVERY:
            return fail('Order is not out for delivery', status_code=400)
        order.update_status(Order.Status.DELIVERED, user=request.user)
        order.award_points()
        SmartTimerAutoClose.objects.filter(order=order).update(is_resolved=True)
        return ok({
            'status': order.status,
            'points_earned': order.points_earned,
            'new_balance': order.customer.loyalty_points,
            'should_rate': True,
        })


class CustomerApproveAdjustmentView(APIView):
    """
    PATCH /orders/:id/approve-adjustment
    Body: { adjustment_id, approved: bool }
    """
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, order_id):
        ser = ApproveAdjustmentSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)

        approved = ser.validated_data['approved']
        adjustment_id = ser.validated_data['adjustment_id']

        try:
            adj = OrderAdjustment.objects.select_related('order', 'order_item').get(
                pk=adjustment_id,
                order__customer=request.user,
            )
        except OrderAdjustment.DoesNotExist:
            return fail('Adjustment not found', status_code=404)

        if adj.customer_approval_status and adj.customer_approval_status != 'pending':
            return fail('Adjustment already responded to', status_code=400)

        adj.customer_approval_status = 'approved' if approved else 'rejected'
        adj.customer_approved = approved
        adj.customer_approval_at = timezone.now()
        adj.save(update_fields=['customer_approval_status', 'customer_approved',
                                'customer_approval_at'])

        item = adj.order_item
        order = adj.order

        with transaction.atomic():
            if adj.action_type in ('price_change',):
                if approved and item:
                    try:
                        item.final_unit_price = float(adj.new_value)
                        item.final_price = item.final_unit_price
                        item.status = OrderItem.ItemStatus.PRICE_ADJUSTED
                        item.save(update_fields=['final_unit_price', 'final_price', 'status'])
                    except (TypeError, ValueError):
                        pass
                elif item:
                    item.status = OrderItem.ItemStatus.REJECTED
                    item.save(update_fields=['status'])
            elif adj.action_type in ('qty_change', 'quantity_change'):
                if approved and item:
                    try:
                        item.actual_qty = float(adj.new_value)
                        item.delivered_quantity = item.actual_qty
                        item.save(update_fields=['actual_qty', 'delivered_quantity'])
                    except (TypeError, ValueError):
                        pass
            elif adj.action_type in ('substitute_suggested', 'substitute'):
                if approved and item:
                    # Swap the line to the approved substitute (new product + price).
                    item.apply_substitute()
                elif item:
                    # Declined → drop the item from the order entirely, so it is
                    # neither charged nor shown on the order/receipt.
                    item.status = OrderItem.ItemStatus.REMOVED
                    item.save(update_fields=['status'])
            elif adj.action_type in ('weight_diff_sent',):
                if item:
                    item.weight_difference_approved = approved
                    if approved:
                        item.status = OrderItem.ItemStatus.WEIGHT_ADJUSTED
                    item.save(update_fields=['weight_difference_approved', 'status'])
            elif adj.action_type in ('item_added',):
                if not approved and item:
                    item.status = OrderItem.ItemStatus.REMOVED
                    item.save(update_fields=['status'])

            old_total = order.total_amount  # capture before recalculate
            order.calculate_totals()
            new_total = order.total_amount

        # ── Post-approval: wallet refund (price decreased) ────────────────────
        wallet_refund = None
        if approved and adj.action_type == 'price_change':
            try:
                diff = float(old_total) - float(new_total)
                if diff > 0:
                    # Order was paid online or via wallet — refund excess to wallet
                    if order.payment_method in (
                        Order.PaymentMethod.ONLINE,
                        Order.PaymentMethod.WALLET,
                    ):
                        from apps.users.models import WalletTransaction
                        new_balance = float(
                            getattr(request.user, 'wallet_balance', 0) or 0
                        ) + diff
                        request.user.wallet_balance = new_balance
                        request.user.save(update_fields=['wallet_balance'])
                        WalletTransaction.objects.create(
                            user=request.user,
                            type=WalletTransaction.Type.CREDIT,
                            amount=diff,
                            reason=WalletTransaction.Reason.REFUND,
                            reference_id=str(order.id),
                            reference_type='order',
                            balance_after=new_balance,
                        )
                        wallet_refund = round(diff, 2)
                        # Notify customer about wallet refund
                        from apps.notifications.utils import send_push_notification
                        send_push_notification(
                            user=request.user,
                            title_ar='تم إضافة المبلغ لمحفظتك 💰',
                            title_en='Wallet refund applied',
                            body_ar=f'تم إضافة {diff:.2f} جنيه لمحفظتك',
                            body_en=f'{diff:.2f} EGP refunded to your wallet',
                            data={'type': 'wallet_refund', 'amount': str(round(diff, 2)),
                                  'order_id': str(order.id)},
                        )
            except Exception:
                pass

        # ── Notify the agent ──────────────────────────────────────────────────
        try:
            from apps.notifications.utils import send_push_notification
            agent = adj.preparer or adj.driver
            if agent:
                send_push_notification(
                    user=agent,
                    title_ar='رد العميل على التعديل',
                    title_en='Customer responded to adjustment',
                    body_ar='قبل' if approved else 'رفض',
                    body_en='Approved' if approved else 'Rejected',
                    data={'type': 'adjustment_response', 'approved': str(approved).lower(),
                          'order_id': str(order.id), 'adjustment_id': str(adj.id)},
                )
        except Exception:
            pass

        # ── Determine if a top-up payment is needed (price increased) ─────────
        payment_required = False
        try:
            if approved and adj.action_type == 'price_change':
                diff_owed = float(new_total) - float(old_total)
                if diff_owed > 0 and order.payment_method == Order.PaymentMethod.ONLINE:
                    payment_required = True
                    adj.new_total = new_total
                    adj.save(update_fields=['new_total'])
        except Exception:
            pass

        response_data = {
            'approved': approved,
            'new_total': str(order.total_amount),
            'adjustment_id': adj.id,
            'payment_required': payment_required,
        }
        if wallet_refund is not None:
            response_data['wallet_refund'] = wallet_refund
        if payment_required:
            try:
                response_data['amount_owed'] = str(round(float(new_total) - float(old_total), 2))
            except Exception:
                pass

        return ok(response_data)


class CustomerAddItemView(APIView):
    """POST /orders/:id/items — customer adds an item to a preparing order."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, order_id):
        ser = AddItemSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        qs = Order.objects.filter(customer=request.user)
        order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
                 or qs.filter(id=order_id).first())
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.PREPARING:
            return fail('Items can only be added while order is preparing', status_code=400)
        try:
            product = Product.objects.get(id=ser.validated_data['product_id'], store_id=order.store_id)
        except Product.DoesNotExist:
            return fail('Product not found or not in this store', status_code=404)
        qty = ser.validated_data['qty']
        item = OrderItem.objects.create(
            order=order, product=product,
            product_name_ar=product.name_ar, product_name_en=product.name_en,
            product_barcode=product.barcode or '',
            unit_type=product.sell_unit,
            quantity=qty, requested_qty=qty,
            unit_price=product.current_price,
            status=OrderItem.ItemStatus.ADDED,
        )
        order.calculate_totals()

        # Notify preparer
        if order.preparer:
            try:
                from apps.notifications.utils import send_push_notification
                send_push_notification(
                    user=order.preparer,
                    title_ar='العميل أضاف صنف جديد',
                    title_en='Customer added an item',
                    body_ar=f'{product.name_ar} × {qty}',
                    body_en=f'{product.name_en} × {qty}',
                    data={'type': 'customer_added_item', 'order_id': str(order.id),
                          'item_id': str(item.id)},
                )
            except Exception:
                pass
        return ok(OrderItemSerializer(item, context={'request': request}).data,
                  message='Item added', status_code=201)


class CustomerRemoveItemView(APIView):
    """DELETE /orders/:id/items/:itemId — customer removes an item from a preparing order."""
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, order_id, item_id):
        qs = Order.objects.filter(customer=request.user)
        order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
                 or qs.filter(id=order_id).first())
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.PREPARING:
            return fail('Items can only be removed while order is preparing', status_code=400)
        try:
            item = order.items.get(pk=item_id)
        except OrderItem.DoesNotExist:
            return fail('Item not found in this order', status_code=404)
        item.status = OrderItem.ItemStatus.REMOVED
        item.save(update_fields=['status'])
        order.calculate_totals()
        return ok({'removed': True, 'new_total': str(order.total_amount)})


# ─── Rating endpoints (customer side) ─────────────────────────────────────────

class RatingCreateView(APIView):
    """
    POST /api/ratings/
    Body: { order_id, product_quality_rating, delivery_speed_rating, comment?, photo_url? }
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        order_id = request.data.get('order_id')
        if not order_id:
            return fail('order_id required', status_code=400)
        qs = Order.objects.filter(customer=request.user)
        order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
                 or qs.filter(id=order_id).first())
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.DELIVERED:
            return fail('Can only rate delivered orders', status_code=400)
        if hasattr(order, 'rating'):
            return fail('Already rated this order', status_code=400)
        ser = OrderRatingSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        rating = ser.save(order=order, customer=request.user)
        # Recompute driver avg rating
        if order.driver:
            avg = (OrderRating.objects.filter(order__driver=order.driver)
                   .values_list('delivery_rating', flat=True))
            avg_list = list(avg)
            if avg_list:
                order.driver.rating = round(sum(avg_list) / len(avg_list), 2)
                order.driver.save(update_fields=['rating'])
        # Bonus loyalty points
        from apps.notifications.models import AppSettings
        try:
            bonus = int(AppSettings.get('rating_bonus_points', '5') or 5)
        except (TypeError, ValueError):
            bonus = 5
        request.user.loyalty_points += bonus
        request.user.save(update_fields=['loyalty_points'])
        return ok({
            'rating_id': rating.id,
            'points_bonus': bonus,
            'new_balance': request.user.loyalty_points,
        }, status_code=201)


class RatingUpdateView(generics.RetrieveUpdateAPIView):
    """PATCH /api/ratings/:id — must be the rating owner."""
    serializer_class = OrderRatingSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return OrderRating.objects.filter(customer=self.request.user)


class PreparerRatingsView(generics.ListAPIView):
    """GET /api/ratings/preparer/:preparerId — ratings on orders this preparer prepared."""
    serializer_class = OrderRatingSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        preparer_id = self.kwargs['preparer_id']
        return OrderRating.objects.filter(order__preparer_id=preparer_id)
