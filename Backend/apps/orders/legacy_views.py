"""
Legacy compatibility endpoints for the existing Flutter client (customer + driver
share the same codebase using paths like /orders/<id>/accept/, /orders/<id>/
mark-delivered/, /orders/adjustments/<id>/respond/, /orders/<id>/rate/, etc.).

These views just delegate to the canonical handlers under /api/v1/agent/ or
/api/v1/ratings/ so the old client keeps working without changes.
"""
from rest_framework import permissions, generics
from rest_framework.views import APIView

from .models import Order, OrderAdjustment
from .views import RatingCreateView
from .serializers import OrderRatingSerializer, OrderListSerializer
from . import agent_views as av
from apps.core.permissions import IsAgent
from apps.core.responses import ok, fail


# ─── /orders/<id>/accept/ — legacy driver accept (delegates to agent) ─────────

class LegacyDriverAcceptView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        # Old code uses POST, new uses PATCH — both reach the same handler.
        return av.AgentAcceptOrderView().patch(request, order_id)


class LegacyDriverStartPreparingView(APIView):
    """POST /orders/<id>/start-preparing/ — accepted → preparing."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        return av.AgentStartPreparingView().patch(request, order_id)


class LegacyDriverStartDeliveryView(APIView):
    """POST /orders/<id>/start-delivery/ — preparing → out_for_delivery (order ready)."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        return av.AgentReadyView().patch(request, order_id)


class LegacyDriverMarkDeliveredView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        return av.AgentDeliveredView().patch(request, order_id)


class LegacyDriverAutoCloseView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        return av.AgentForceCloseView().patch(request, order_id)


class LegacyDriverAdjustPriceView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id, item_id):
        return av.AgentItemAdjustPriceView().patch(request, order_id, item_id)


class LegacyDriverSubstituteView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id, item_id):
        return av.AgentItemSubstituteView().post(request, order_id, item_id)


class LegacyDriverAddItemView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request, order_id):
        return av.AgentAddItemView().post(request, order_id)


# ─── /orders/adjustments/<id>/respond/ — legacy customer approval ─────────────

class LegacyApproveAdjustmentView(APIView):
    """
    Old shape: POST /orders/adjustments/<id>/respond/  body: { approved: bool }
    New shape: PATCH /orders/<order_id>/approve-adjustment/  body: { adjustment_id, approved }

    Re-implements the approval flow locally to avoid mutating request.data.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, adjustment_id):
        from django.utils import timezone
        from django.db import transaction
        from .models import OrderItem
        from apps.notifications.utils import send_push_notification

        try:
            adj = OrderAdjustment.objects.select_related('order', 'order_item').get(
                pk=adjustment_id, order__customer=request.user,
            )
        except OrderAdjustment.DoesNotExist:
            return fail('Adjustment not found', status_code=404)

        if adj.customer_approval_status and adj.customer_approval_status != 'pending':
            return fail('Adjustment already responded to', status_code=400)

        approved = bool(request.data.get('approved'))
        adj.customer_approval_status = 'approved' if approved else 'rejected'
        adj.customer_approved = approved
        adj.customer_approval_at = timezone.now()
        adj.save(update_fields=['customer_approval_status', 'customer_approved',
                                'customer_approval_at'])

        item = adj.order_item
        order = adj.order
        with transaction.atomic():
            if adj.action_type == 'price_change' and item:
                if approved:
                    try:
                        item.final_unit_price = float(adj.new_value)
                        item.final_price = item.final_unit_price
                        item.status = OrderItem.ItemStatus.PRICE_ADJUSTED
                        item.save(update_fields=['final_unit_price', 'final_price', 'status'])
                    except (TypeError, ValueError):
                        pass
                else:
                    item.status = OrderItem.ItemStatus.REJECTED
                    item.save(update_fields=['status'])
            elif adj.action_type in ('qty_change', 'quantity_change') and item and approved:
                try:
                    item.actual_qty = float(adj.new_value)
                    item.delivered_quantity = item.actual_qty
                    item.save(update_fields=['actual_qty', 'delivered_quantity'])
                except (TypeError, ValueError):
                    pass
            elif adj.action_type in ('substitute_suggested', 'substitute') and item:
                if approved:
                    # Swap the line to the approved substitute (new product + price).
                    item.apply_substitute()
                else:
                    # Declined → original stays unavailable, so it isn't charged.
                    item.status = OrderItem.ItemStatus.UNAVAILABLE
                    item.save(update_fields=['status'])
            elif adj.action_type == 'weight_diff_sent' and item:
                item.weight_difference_approved = approved
                if approved:
                    item.status = OrderItem.ItemStatus.WEIGHT_ADJUSTED
                item.save(update_fields=['weight_difference_approved', 'status'])
            elif adj.action_type == 'item_added' and item and not approved:
                item.status = OrderItem.ItemStatus.REMOVED
                item.save(update_fields=['status'])

            order.calculate_totals()

        agent = adj.preparer or adj.driver
        if agent:
            try:
                send_push_notification(
                    user=agent,
                    title_ar='رد العميل على التعديل',
                    title_en='Customer responded',
                    body_ar='قبل' if approved else 'رفض',
                    body_en='Approved' if approved else 'Rejected',
                    data={'type': 'adjustment_response',
                          'approved': str(approved).lower(),
                          'order_id': str(order.id),
                          'adjustment_id': str(adj.id)},
                )
            except Exception:
                pass

        return ok({
            'approved': approved,
            'new_total': str(order.total_amount),
            'adjustment_id': adj.id,
        })


class LegacyDriverOrderListView(generics.ListAPIView):
    """Legacy /orders/driver/list/ — proxies to AgentOrderListView."""
    serializer_class = OrderListSerializer
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def get_queryset(self):
        return av.AgentOrderListView.get_queryset(self)


# ─── /orders/<id>/rate/ — legacy rating create ────────────────────────────────

class LegacyRateOrderView(APIView):
    """
    Old shape: POST /orders/<order_id>/rate/ with body { product_rating, delivery_rating, comment? }
    New shape: POST /ratings/ with order_id + product_quality_rating + delivery_speed_rating
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, order_id):
        try:
            order = Order.objects.get(order_number=order_id, customer=request.user)
        except Order.DoesNotExist:
            try:
                order = Order.objects.get(order_id=order_id, customer=request.user)
            except Order.DoesNotExist:
                try:
                    order = Order.objects.get(id=order_id, customer=request.user)
                except Order.DoesNotExist:
                    return fail('Order not found', status_code=404)

        if order.status != Order.Status.DELIVERED:
            return fail('Can only rate delivered orders', status_code=400)
        if hasattr(order, 'rating'):
            return fail('Already rated this order', status_code=400)

        body = dict(request.data) if hasattr(request.data, 'items') else {}
        # Accept either spec aliases or legacy field names.
        body.setdefault('product_quality_rating', body.get('product_rating'))
        body.setdefault('delivery_speed_rating', body.get('delivery_rating'))

        ser = OrderRatingSerializer(data=body)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        rating = ser.save(order=order, customer=request.user)

        # Award bonus points
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
