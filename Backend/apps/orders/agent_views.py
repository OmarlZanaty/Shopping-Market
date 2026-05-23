"""
Agent (preparer + driver) endpoints under /api/v1/agent/.
Auth + IsAgent (role IN preparer, driver). Branch-scoped to assigned orders.
"""
from decimal import Decimal
from urllib.parse import quote

from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from django.db import transaction
from django.utils import timezone

from .models import Order, OrderItem, OrderAdjustment, SmartTimerAutoClose
from .serializers import (
    OrderSerializer, OrderListSerializer, OrderItemSerializer,
    AdjustPriceSerializer, AdjustQuantitySerializer, AdjustWeightSerializer,
    SubstituteItemSerializer, AddItemSerializer, DriverDeliveredSerializer,
    ActionLogSerializer, OrderAdjustmentSerializer,
)
from apps.products.models import Product, ProductBranch
from apps.users.models import DataShareLog
from apps.core.permissions import IsAgent, IsPreparer, IsDriver
from apps.core.responses import ok, fail


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _lookup_order_for_agent(order_id, user):
    qs = Order.objects.filter(store_id=user.store_id) if user.store_id else Order.objects.all()
    order = (qs.filter(order_number=order_id).first() or qs.filter(order_id=order_id).first()
             or qs.filter(id=order_id).first())
    if not order:
        return None
    # Visible only if assigned to this agent OR unassigned (pool)
    if order.preparer_id == user.id or order.driver_id == user.id:
        return order
    if order.preparer_id is None and order.driver_id is None:
        return order
    # Branch managers' branch_id matches?
    if user.role == 'branch_manager' and order.branch_id == user.branch_id:
        return order
    return None


def _push(user, title_ar, title_en, body_ar, body_en, data=None):
    from apps.notifications.utils import send_push_notification
    try:
        send_push_notification(user, title_ar, title_en, body_ar, body_en, data=data)
    except Exception:
        pass


def _schedule_approval_timeout(adjustment):
    """Spec: 15-min timer to remind agent if customer doesn't respond."""
    from .tasks import approval_timeout_remind
    from django.conf import settings
    deadline = timezone.now() + timezone.timedelta(
        minutes=getattr(settings, 'WEIGHT_DIFF_APPROVAL_TIMEOUT_MINS', 15)
    )
    adjustment.approval_deadline = deadline
    adjustment.save(update_fields=['approval_deadline'])
    try:
        task = approval_timeout_remind.apply_async(args=[adjustment.id], eta=deadline)
        adjustment.timeout_task_id = task.id
        adjustment.save(update_fields=['timeout_task_id'])
    except Exception:
        pass


# ─── Order list & detail ─────────────────────────────────────────────────────

class AgentOrderListView(generics.ListAPIView):
    serializer_class = OrderListSerializer
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def get_queryset(self):
        u = self.request.user
        qs = Order.objects.select_related('customer', 'branch', 'store')
        if u.role == 'preparer':
            qs = qs.filter(preparer=u) | qs.filter(preparer__isnull=True, status='new')
        elif u.role == 'driver':
            qs = qs.filter(driver=u) | qs.filter(driver__isnull=True, status='out_for_delivery')
        if u.store_id:
            qs = qs.filter(store_id=u.store_id)
        if u.branch_id:
            qs = qs.filter(branch_id=u.branch_id)
        status_filter = self.request.query_params.get('status')
        if status_filter:
            qs = qs.filter(status=status_filter)
        return qs.distinct().order_by('-created_at')


class AgentOrderDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def get(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        return ok(OrderSerializer(order, context={'request': request}).data)


# ─── Lifecycle transitions ───────────────────────────────────────────────────

class AgentAcceptOrderView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.NEW:
            return fail(f'Cannot accept order in status "{order.status}"', status_code=400)
        if request.user.role == 'preparer':
            order.preparer = request.user
        else:
            order.driver = request.user
        order.save(update_fields=['preparer', 'driver'])
        order.update_status(Order.Status.ACCEPTED, user=request.user)
        return ok(OrderSerializer(order, context={'request': request}).data)


class AgentRejectOrderView(APIView):
    """Preparer/driver declines an unassigned-or-just-assigned order."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if request.user.role == 'preparer' and order.preparer_id == request.user.id:
            order.preparer = None
        elif request.user.role == 'driver' and order.driver_id == request.user.id:
            order.driver = None
        else:
            return fail('Cannot reject an order you do not own', status_code=400)
        order.status = Order.Status.NEW
        order.save(update_fields=['preparer', 'driver', 'status'])
        # Re-notify admins
        from .services import _notify_admin_new_order
        _notify_admin_new_order(order)
        return ok({'status': order.status})


class AgentStartPreparingView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsPreparer]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.ACCEPTED:
            return fail('Order must be in "accepted" status', status_code=400)
        order.update_status(Order.Status.PREPARING, user=request.user)
        return ok(OrderSerializer(order, context={'request': request}).data)


class AgentReadyView(APIView):
    """Preparer marks order as ready for pickup by driver. Status → out_for_delivery."""
    permission_classes = [permissions.IsAuthenticated, IsPreparer]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.PREPARING:
            return fail('Order must be in "preparing" status', status_code=400)
        order.update_status(Order.Status.OUT_FOR_DELIVERY, user=request.user)
        return ok({'status': order.status})


class AgentPickedUpView(APIView):
    """Driver confirms pickup from preparer. Records timestamp."""
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.OUT_FOR_DELIVERY:
            return fail('Order must be ready (out_for_delivery)', status_code=400)
        if not order.driver_id:
            order.driver = request.user
        order.out_for_delivery_at = timezone.now()
        order.save(update_fields=['driver', 'out_for_delivery_at'])
        return ok({'status': order.status, 'picked_up_at': order.out_for_delivery_at})


class AgentDeliveredView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def patch(self, request, order_id):
        ser = DriverDeliveredSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.status != Order.Status.OUT_FOR_DELIVERY:
            return fail('Order must be out for delivery', status_code=400)
        if order.driver_id != request.user.id:
            return fail('Not your delivery', status_code=403)

        order.amount_collected = ser.validated_data.get('amount_collected') or order.total_amount
        order.delivery_photo_url = ser.validated_data.get('delivery_photo_url', '')
        if 'proof_image' in request.FILES:
            order.driver_proof_image = request.FILES['proof_image']
        order.save(update_fields=['amount_collected', 'delivery_photo_url', 'driver_proof_image'])

        # Set the 2hr auto-close timer
        from django.conf import settings as django_settings
        hours = getattr(django_settings, 'AUTO_CLOSE_TIMEOUT_HOURS', 2)
        auto_close_at = timezone.now() + timezone.timedelta(hours=hours)
        SmartTimerAutoClose.objects.update_or_create(
            order=order,
            defaults={'auto_close_scheduled_at': auto_close_at, 'is_resolved': False},
        )
        try:
            from .tasks import auto_close_order
            auto_close_order.apply_async(args=[str(order.id)], eta=auto_close_at)
        except Exception:
            pass

        # Add cash to driver's running total
        if order.payment_method == Order.PaymentMethod.CASH:
            request.user.cash_on_hand = float(request.user.cash_on_hand) + float(order.amount_collected)
            request.user.save(update_fields=['cash_on_hand'])

        return ok({'message': 'Marked as delivered. Awaiting customer confirmation.',
                   'auto_close_at': auto_close_at})


class AgentForceCloseView(APIView):
    """
    Driver force-closes after 2hr if customer didn't confirm.
    Requires delivery_photo_url.
    """
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def patch(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        if order.driver_id != request.user.id:
            return fail('Not your delivery', status_code=403)
        timer = SmartTimerAutoClose.objects.filter(order=order, is_resolved=False).first()
        if not timer:
            return fail('No auto-close timer set', status_code=400)
        if timezone.now() < timer.auto_close_scheduled_at:
            remaining = int((timer.auto_close_scheduled_at - timezone.now()).total_seconds() // 60)
            return fail(f'Too early. {remaining} minutes remaining', status_code=400)

        photo = request.data.get('delivery_photo_url') or order.delivery_photo_url
        if not photo:
            return fail('delivery_photo_url is required to force-close', status_code=400)
        order.delivery_photo_url = photo
        order.closed_by = Order.ClosedBy.DRIVER
        order.closed_by_driver_at = timezone.now()
        order.save(update_fields=['delivery_photo_url', 'closed_by', 'closed_by_driver_at'])
        order.update_status(Order.Status.DELIVERED, user=request.user)
        order.award_points()
        timer.is_resolved = True
        timer.save(update_fields=['is_resolved'])
        return ok({'closed': True, 'order_id': str(order.id)})


# ─── Item-level actions ──────────────────────────────────────────────────────

def _resolve_item(order_id, item_id, user):
    order = _lookup_order_for_agent(order_id, user)
    if not order:
        return None, fail('Order not found', status_code=404)
    try:
        item = order.items.get(pk=item_id)
    except OrderItem.DoesNotExist:
        return None, fail('Item not found in this order', status_code=404)
    return item, None


class AgentItemAdjustQtyView(APIView):
    """PATCH /agent/orders/:orderId/items/:itemId/qty — body: { actual_qty }."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id, item_id):
        ser = AdjustQuantitySerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err

        new_qty = ser.validated_data['actual_qty']
        old_qty = item.quantity
        item.actual_qty = new_qty
        item.save(update_fields=['actual_qty'])

        adj = OrderAdjustment.objects.create(
            order=item.order, order_item=item, preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.QTY_CHANGE,
            old_value=str(old_qty), new_value=str(new_qty),
            reason=ser.validated_data.get('reason', ''),
            customer_approval_status=OrderAdjustment.ApprovalStatus.PENDING,
        )
        # Notify customer if difference is significant (>10%)
        if old_qty and abs((new_qty - old_qty) / old_qty) > Decimal('0.10'):
            _push(item.order.customer,
                  'تم تعديل كمية صنف', 'Item quantity adjusted',
                  f'{item.product_name_ar}: {old_qty} → {new_qty}',
                  f'{item.product_name_en}: {old_qty} → {new_qty}',
                  data={'type': 'quantity_change', 'order_id': str(item.order.id),
                        'adjustment_id': str(adj.id)})
        return ok({'adjustment_id': adj.id, 'actual_qty': str(new_qty)})


class AgentItemUnavailableView(APIView):
    """PATCH /agent/orders/:orderId/items/:itemId/unavailable"""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id, item_id):
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err
        item.status = OrderItem.ItemStatus.UNAVAILABLE
        item.save(update_fields=['status'])
        adj = OrderAdjustment.objects.create(
            order=item.order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.ITEM_REMOVED,
            new_value=item.product_name_en,
            reason='Out of stock',
        )
        _push(item.order.customer,
              'صنف غير متوفر', 'Item unavailable',
              f'{item.product_name_ar} غير متوفر — قم باختيار بديل',
              f'{item.product_name_en} is unavailable — pick an alternative',
              data={'type': 'unavailable', 'order_id': str(item.order.id),
                    'item_id': str(item.id), 'adjustment_id': str(adj.id)})
        # Suggest alternatives automatically
        alts = list(item.product.alternative_products.filter(is_available=True)[:3]
                    .values('id', 'name_ar', 'name_en', 'original_price'))
        return ok({'adjustment_id': adj.id, 'alternatives': alts})


class AgentItemAdjustPriceView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id, item_id):
        ser = AdjustPriceSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err
        new_price = ser.validated_data['new_price']
        adj = OrderAdjustment.objects.create(
            order=item.order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.PRICE_CHANGE,
            old_value=str(item.unit_price), new_value=str(new_price),
            reason=ser.validated_data.get('reason', ''),
            customer_approval_status=OrderAdjustment.ApprovalStatus.PENDING,
        )
        _push(item.order.customer,
              'تعديل سعر منتج', 'Price change request',
              f'تغير سعر {item.product_name_ar} من {item.unit_price} إلى {new_price} جنيه',
              f'{item.product_name_en} price changed from {item.unit_price} to {new_price} EGP',
              data={'type': 'price_change', 'order_id': str(item.order.id),
                    'adjustment_id': str(adj.id), 'item_id': str(item.id)})
        _schedule_approval_timeout(adj)
        return ok({'adjustment_id': adj.id})


class AgentItemAdjustWeightView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, order_id, item_id):
        ser = AdjustWeightSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err
        weight_actual = ser.validated_data['weight_actual']
        weight_ordered = item.weight_ordered or item.quantity
        item.weight_actual = weight_actual
        if not item.weight_ordered:
            item.weight_ordered = weight_ordered
        # Compute price diff
        price_diff = (Decimal(str(weight_actual)) - Decimal(str(weight_ordered))) * Decimal(str(item.unit_price))
        item.weight_variance = Decimal(str(weight_actual)) - Decimal(str(weight_ordered))
        item.weight_variance_amount = price_diff
        item.save(update_fields=['weight_actual', 'weight_ordered', 'weight_variance', 'weight_variance_amount'])

        adj = OrderAdjustment.objects.create(
            order=item.order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.WEIGHT_DIFF_SENT,
            old_value=str(weight_ordered), new_value=str(weight_actual),
            reason=ser.validated_data.get('reason', ''),
            customer_approval_status=OrderAdjustment.ApprovalStatus.PENDING,
        )
        _push(item.order.customer,
              'فرق في وزن المنتج', 'Weight difference',
              f'{item.product_name_ar}: {weight_ordered}kg → {weight_actual}kg',
              f'{item.product_name_en}: {weight_ordered}kg → {weight_actual}kg',
              data={'type': 'weight_diff', 'order_id': str(item.order.id),
                    'adjustment_id': str(adj.id), 'item_id': str(item.id),
                    'price_diff': str(price_diff)})
        _schedule_approval_timeout(adj)
        return ok({'adjustment_id': adj.id, 'price_diff': str(price_diff)})


class AgentItemSubstituteView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id, item_id):
        ser = SubstituteItemSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err
        try:
            substitute = Product.objects.get(
                id=ser.validated_data['substitute_product_id'],
                is_available=True,
                store_id=item.order.store_id,
            )
        except Product.DoesNotExist:
            return fail('Substitute product not found or not in this store', status_code=404)

        item.substitute_product = substitute
        item.status = OrderItem.ItemStatus.UNAVAILABLE
        item.save(update_fields=['substitute_product', 'status'])

        adj = OrderAdjustment.objects.create(
            order=item.order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.SUBSTITUTE_SUGGESTED,
            old_value=item.product_name_en, new_value=substitute.name_en,
            reason=ser.validated_data.get('reason', ''),
            customer_approval_status=OrderAdjustment.ApprovalStatus.PENDING,
        )
        _push(item.order.customer,
              'اقتراح بديل للمنتج', 'Substitute suggested',
              f'البديل: {substitute.name_ar}',
              f'Suggested: {substitute.name_en}',
              data={'type': 'alternative', 'order_id': str(item.order.id),
                    'adjustment_id': str(adj.id), 'item_id': str(item.id),
                    'substitute_product_id': str(substitute.id),
                    'substitute_price': str(substitute.current_price)})
        _schedule_approval_timeout(adj)
        return ok({'adjustment_id': adj.id})


class AgentAddItemView(APIView):
    """POST /agent/orders/:orderId/items/add — agent adds item (customer must approve)."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        ser = AddItemSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        try:
            product = Product.objects.get(
                id=ser.validated_data['product_id'],
                store_id=order.store_id,
            )
        except Product.DoesNotExist:
            return fail('Product not in this store', status_code=404)
        qty = ser.validated_data['qty']
        item = OrderItem.objects.create(
            order=order, product=product,
            product_name_ar=product.name_ar, product_name_en=product.name_en,
            product_barcode=product.barcode or '',
            unit_type=product.sell_unit,
            quantity=qty, requested_qty=qty,
            unit_price=product.current_price,
            added_by_agent=True, added_by_driver=request.user.role == 'driver',
            status=OrderItem.ItemStatus.ADDED,
        )
        adj = OrderAdjustment.objects.create(
            order=order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.ITEM_ADDED,
            new_value=f'{product.name_en} x{qty}',
            reason=ser.validated_data.get('reason', ''),
            customer_approval_status=OrderAdjustment.ApprovalStatus.PENDING,
        )
        _push(order.customer,
              'إضافة صنف جديد للطلب', 'Item added to order',
              f'{product.name_ar} × {qty}',
              f'{product.name_en} × {qty}',
              data={'type': 'item_added', 'order_id': str(order.id),
                    'adjustment_id': str(adj.id), 'item_id': str(item.id)})
        _schedule_approval_timeout(adj)
        return ok({'item_id': item.id, 'adjustment_id': adj.id}, status_code=201)


class AgentRemoveItemView(APIView):
    """DELETE /agent/orders/:orderId/items/:itemId"""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def delete(self, request, order_id, item_id):
        item, err = _resolve_item(order_id, item_id, request.user)
        if err:
            return err
        item.status = OrderItem.ItemStatus.REMOVED
        item.save(update_fields=['status'])
        OrderAdjustment.objects.create(
            order=item.order, order_item=item,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.ITEM_REMOVED,
            old_value=item.product_name_en,
            reason='Removed by agent',
        )
        item.order.calculate_totals()
        return ok({'removed': True, 'new_total': str(item.order.total_amount)})


# ─── Inventory ───────────────────────────────────────────────────────────────

class AgentInventoryScanView(APIView):
    """GET /agent/inventory/scan/:barcode"""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def get(self, request, barcode):
        u = request.user
        qs = Product.objects.filter(barcode=barcode)
        if u.store_id:
            qs = qs.filter(store_id=u.store_id)
        product = qs.first()
        if not product:
            return fail('Product not found', status_code=404)

        branch_id = u.branch_id
        branch_stock = None
        if branch_id:
            ps = ProductBranch.objects.filter(product=product, branch_id=branch_id).first()
            branch_stock = ps.stock_quantity if ps else 0

        # Log the scan
        # No specific order in this context — we log without order_item
        OrderAdjustment.objects.create(
            order_id=None,
            preparer=u if u.role == 'preparer' else None,
            driver=u if u.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.BARCODE_SCANNED,
            new_value=barcode,
            reason='Inventory scan',
        ) if False else None  # cannot create OrderAdjustment without order; skip silently

        return ok({
            'id': str(product.id),
            'name_ar': product.name_ar,
            'name_en': product.name_en,
            'barcode': product.barcode,
            'current_price': str(product.current_price),
            'is_available': product.is_available,
            'stock_quantity': product.quantity_in_stock,
            'branch_stock': branch_stock,
            'is_weight_based': product.is_weight_based,
        })


class AgentMarkAvailableView(APIView):
    """PATCH /agent/inventory/mark-available/:productId"""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, product_id):
        u = request.user
        qs = Product.objects.filter(pk=product_id)
        if u.store_id:
            qs = qs.filter(store_id=u.store_id)
        product = qs.first()
        if not product:
            return fail('Product not found', status_code=404)
        product.is_available = True
        product.save(update_fields=['is_available'])
        if u.branch_id:
            ProductBranch.objects.update_or_create(
                product=product, branch_id=u.branch_id,
                defaults={'is_available': True},
            )
        try:
            from .tasks import notify_stock_waitlist
            notify_stock_waitlist.delay(str(product.id))
        except Exception:
            pass
        return ok({'is_available': True, 'product_id': str(product.id)})


class AgentToggleAvailabilityView(APIView):
    """PATCH /agent/inventory/toggle/:productId — flips is_available on/off."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def patch(self, request, product_id):
        u = request.user
        qs = Product.objects.filter(pk=product_id)
        if u.store_id:
            qs = qs.filter(store_id=u.store_id)
        product = qs.first()
        if not product:
            return fail('Product not found', status_code=404)

        product.is_available = not product.is_available
        product.save(update_fields=['is_available'])

        if u.branch_id:
            ProductBranch.objects.update_or_create(
                product=product, branch_id=u.branch_id,
                defaults={'is_available': product.is_available},
            )

        # Notify waitlist only when turning ON
        if product.is_available:
            try:
                from .tasks import notify_stock_waitlist
                notify_stock_waitlist.delay(str(product.id))
            except Exception:
                pass

        return ok({'is_available': product.is_available, 'product_id': str(product.id)})


class AgentInventoryListView(APIView):
    """GET /agent/inventory/products/ — paginated product list for the agent.

    Query params:
        q          — search (name_ar / name_en / barcode)
        available  — 1 | 0
        page       — 1-based page number (default 1)
        limit      — page size (default 40, max 100)
    """
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def get(self, request):
        from django.db.models import Case, When, F, DecimalField, Q as DQ
        u = request.user
        qs = Product.objects.all().order_by('name_ar')
        if u.store_id:
            qs = qs.filter(store_id=u.store_id)

        # Search
        q = request.query_params.get('q', '').strip()
        if q:
            qs = qs.filter(
                DQ(name_ar__icontains=q) | DQ(name_en__icontains=q) | DQ(barcode__icontains=q)
            )

        # Availability filter
        available_param = request.query_params.get('available')
        if available_param is not None:
            qs = qs.filter(is_available=(available_param.lower() in ('1', 'true', 'yes')))

        # Total count (before slicing)
        total = qs.count()

        # Pagination
        try:
            limit = min(int(request.query_params.get('limit', 40)), 100)
            page  = max(int(request.query_params.get('page', 1)), 1)
        except (ValueError, TypeError):
            limit, page = 40, 1
        offset = (page - 1) * limit
        total_pages = max(1, (total + limit - 1) // limit)

        # Annotate effective price
        now = timezone.now()
        qs = qs.annotate(
            current_price=Case(
                When(
                    DQ(discount_price__isnull=False)
                    & (DQ(discount_start__isnull=True) | DQ(discount_start__lte=now))
                    & (DQ(discount_end__isnull=True) | DQ(discount_end__gte=now)),
                    then=F('discount_price'),
                ),
                default=F('original_price'),
                output_field=DecimalField(max_digits=10, decimal_places=2),
            )
        )

        products = list(qs[offset: offset + limit].values(
            'id', 'name_ar', 'name_en', 'barcode',
            'current_price', 'original_price',
            'is_available', 'quantity_in_stock',
            'is_weight_based',
        ))

        for p in products:
            p['id'] = str(p['id'])
            p['current_price'] = float(p['current_price']) if p['current_price'] is not None else 0.0
            p['original_price'] = float(p['original_price']) if p['original_price'] is not None else 0.0

        return Response({
            'success': True,
            'data': products,
            'pagination': {
                'page': page,
                'limit': limit,
                'total': total,
                'totalPages': total_pages,
                'hasMore': page < total_pages,
            },
            'message': '',
            'errors': [],
        })


# ─── Action log ──────────────────────────────────────────────────────────────

class AgentActionLogView(APIView):
    """
    POST  /agent/orders/:orderId/log — log an action.
    GET   /agent/orders/:orderId/log — full audit trail.
    """
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        ser = ActionLogSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        adj = OrderAdjustment.objects.create(
            order=order,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=ser.validated_data['action_type'],
            new_value=str(ser.validated_data.get('data', {})),
            reason=ser.validated_data.get('reason', ''),
        )
        return ok({'id': adj.id, 'action_type': adj.action_type}, status_code=201)

    def get(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)
        adjustments = order.adjustments.all().select_related('preparer', 'driver', 'order_item')
        return ok(OrderAdjustmentSerializer(adjustments, many=True).data)


# ─── Share customer data ─────────────────────────────────────────────────────

class AgentShareCustomerDataView(APIView):
    """
    POST /agent/orders/:orderId/share
    Returns a shareable string + Google Maps URL, AND logs that data was shared.
    """
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        order = _lookup_order_for_agent(order_id, request.user)
        if not order:
            return fail('Order not found', status_code=404)

        lat = order.delivery_latitude
        lng = order.delivery_longitude
        maps_url = (
            f'https://www.google.com/maps/dir/?api=1&destination={lat},{lng}'
            if lat and lng else ''
        )
        text = (
            f'Order #{order.order_number}\n'
            f'Customer: {order.delivery_name}\n'
            f'Phone: {order.delivery_phone}\n'
            f'Address: {order.delivery_address}\n'
            f'Building {order.building_number}, Floor {order.floor_number}, Apt {order.apartment_number}\n'
            f'Landmark: {order.landmark}\n'
            f'Maps: {maps_url}'
        )
        whatsapp_url = (
            f'https://wa.me/?text={quote(text)}'
        )

        DataShareLog.objects.create(
            driver=request.user,
            customer=order.customer,
            order=order,
            share_method=request.data.get('method', 'whatsapp'),
        )
        OrderAdjustment.objects.create(
            order=order,
            preparer=request.user if request.user.role == 'preparer' else None,
            driver=request.user if request.user.role == 'driver' else None,
            action_type=OrderAdjustment.AdjustmentType.DATA_SHARED,
            reason=f'shared via {request.data.get("method", "whatsapp")}',
        )

        return ok({
            'text': text,
            'maps_url': maps_url,
            'whatsapp_url': whatsapp_url,
        })
