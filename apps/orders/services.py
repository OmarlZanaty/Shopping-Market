"""
Order business logic — kept separate so views stay thin.
"""
from decimal import Decimal
from django.db import transaction
from django.utils import timezone

from .models import Order, OrderItem, OrderAdjustment
from apps.products.models import Product
from apps.users.models import Address, WalletTransaction, PointsTransaction
from apps.notifications.models import AppSettings


class OrderError(Exception):
    """Business-rule violation during order ops."""


@transaction.atomic
def create_customer_order(customer, payload):
    """
    Build an Order from the spec-shape payload.
    Validates: address ownership, product availability, stock, points balance.
    Deducts stock + points + wallet (if used).
    Returns the created Order.
    """
    address_id = payload['address_id']
    try:
        address = Address.objects.get(pk=address_id, user=customer)
    except Address.DoesNotExist:
        raise OrderError('Address not found or does not belong to current user')

    items_data = payload['items']
    if not items_data:
        raise OrderError('Order must have at least one item')

    # Determine store from first product
    first_product_id = items_data[0]['product_id']
    try:
        first_product = Product.objects.select_for_update().get(id=first_product_id)
    except Product.DoesNotExist:
        raise OrderError('First product not found')
    store_id = first_product.store_id

    # Validate every product is in the same store + available + sufficient stock
    product_ids = [it['product_id'] for it in items_data]
    products = {
        str(p.id): p for p in
        Product.objects.select_for_update().filter(id__in=product_ids)
    }
    if len(products) != len(set(str(pid) for pid in product_ids)):
        raise OrderError('One or more products not found')

    for it in items_data:
        p = products[str(it['product_id'])]
        if p.store_id != store_id:
            raise OrderError(
                'All items must be from the same store. Cross-store carts are not allowed.'
            )
        if not p.is_available:
            raise OrderError(f'{p.name_en} is not available')
        qty_dec = Decimal(str(it['qty']))
        if p.quantity_in_stock < qty_dec:
            raise OrderError(f'Insufficient stock for {p.name_en}')

    # Build order
    delivery_fee = _resolve_delivery_fee(store_id, payload.get('branch_id'))
    order = Order(
        store_id=store_id,
        customer=customer,
        branch_id=payload.get('branch_id'),
        address=address,
        delivery_address=address.full_address,
        building_number=address.building_number,
        floor_number=address.floor_number,
        apartment_number=address.apartment_number,
        landmark=address.landmark,
        delivery_latitude=address.latitude,
        delivery_longitude=address.longitude,
        delivery_name=customer.full_name,
        delivery_phone=customer.phone,
        payment_method=payload.get('payment_method', Order.PaymentMethod.CASH),
        customer_notes=payload.get('notes') or payload.get('customer_notes', ''),
        delivery_fee=delivery_fee,
    )
    order.save()

    subtotal = Decimal('0')
    for it in items_data:
        p = products[str(it['product_id'])]
        qty = Decimal(str(it['qty']))
        price = Decimal(str(p.current_price))
        OrderItem.objects.create(
            order=order,
            product=p,
            product_name_ar=p.name_ar,
            product_name_en=p.name_en,
            product_barcode=p.barcode or '',
            unit_type=p.sell_unit,
            quantity=qty,
            requested_qty=qty,
            unit_price=price,
        )
        subtotal += price * qty
        # Decrement stock
        Product.objects.filter(pk=p.id).update(
            quantity_in_stock=p.quantity_in_stock - int(qty)
        )

    # Apply promo
    promo_discount = Decimal('0')
    promo_code = (payload.get('promo_code') or '').strip()
    if promo_code:
        from apps.promotions.models import Promotion, PromotionUsage
        try:
            promo = Promotion.objects.get(
                code__iexact=promo_code, store_id=store_id,
            )
        except Promotion.DoesNotExist:
            promo = None
        if promo and promo.is_currently_valid:
            cat_ids = list(set(
                cid for p in products.values()
                for cid in p.categories.values_list('id', flat=True)
            ))
            promo_discount = Decimal(str(promo.calculate_discount(float(subtotal), cat_ids)))
            if promo_discount > 0:
                order.promotion_code = promo.code
                order.promotion_discount = promo_discount
                Promotion.objects.filter(pk=promo.pk).update(used_count=promo.used_count + 1)
                # usage row attached after we know the total

    # Apply points
    points_used = int(payload.get('points_to_use', 0) or 0)
    points_value = Decimal('0')
    if points_used > 0:
        if customer.loyalty_points < points_used:
            raise OrderError('Not enough loyalty points')
        try:
            point_val = Decimal(str(AppSettings.get('loyalty_redeem_rate', '0.05') or '0.05'))
        except Exception:
            point_val = Decimal('0.05')
        points_value = Decimal(points_used) * point_val
        customer.loyalty_points -= points_used
        customer.save(update_fields=['loyalty_points'])
        PointsTransaction.objects.create(
            user=customer,
            transaction_type='redeemed',
            points=-points_used,
            balance_after=customer.loyalty_points,
            description=f'Redeemed at checkout for order {order.order_number}',
            order=order,
        )

    # Apply wallet payment if requested
    wallet_used = Decimal('0')
    if order.payment_method == Order.PaymentMethod.WALLET:
        total_pre_wallet = subtotal + order.delivery_fee - promo_discount - points_value
        if customer.wallet_balance < total_pre_wallet:
            raise OrderError('Insufficient wallet balance')
        wallet_used = total_pre_wallet
        customer.wallet_balance -= wallet_used
        customer.save(update_fields=['wallet_balance'])
        WalletTransaction.objects.create(
            user=customer,
            type=WalletTransaction.Type.DEBIT,
            amount=wallet_used,
            reason=WalletTransaction.Reason.ORDER_PAYMENT,
            balance_after=customer.wallet_balance,
            reference_id=str(order.id),
            reference_type='order',
        )
        order.payment_status = Order.PaymentStatus.PAID

    order.subtotal = subtotal
    order.points_used = points_used
    order.points_value = points_value
    order.points_value_used = points_value
    order.total_amount = max(
        Decimal('0'),
        subtotal + order.delivery_fee - promo_discount - points_value,
    )
    if order.payment_method == Order.PaymentMethod.WALLET:
        order.amount_collected = order.total_amount
    order.save()

    # Notify admin
    _notify_admin_new_order(order)

    return order


def _resolve_delivery_fee(store_id, branch_id):
    """Pick a default fee — zone-aware lookup is in promotions.DeliveryFee."""
    from apps.branches.models import Branch
    if branch_id:
        b = Branch.objects.filter(pk=branch_id).first()
        if b:
            return Decimal(str(b.delivery_fee))
    try:
        default = Decimal(str(AppSettings.get('delivery_fee', '15') or '15'))
    except Exception:
        default = Decimal('15')
    return default


def _notify_admin_new_order(order):
    from apps.notifications.utils import send_push_notification
    from django.contrib.auth import get_user_model
    User = get_user_model()
    admins = User.objects.filter(role='admin', is_active=True)
    # Scope: super-admins (store_id IS NULL) + admins of this store
    admins = admins.filter(store_id__in=[None, order.store_id]).distinct()
    for admin in admins:
        send_push_notification(
            user=admin,
            title_ar='طلب جديد!',
            title_en='New Order!',
            body_ar=f'طلب جديد رقم {order.order_number} من {order.customer.full_name}',
            body_en=f'New order #{order.order_number} from {order.customer.full_name}',
            data={'type': 'new_order', 'order_id': str(order.id),
                  'order_number': order.order_number, 'store_id': order.store_id},
        )


@transaction.atomic
def cancel_order(order, by_user, reason=''):
    if order.status not in (Order.Status.NEW, Order.Status.ACCEPTED, Order.Status.PREPARING):
        raise OrderError(
            f'Cannot cancel an order in status "{order.status}". Allowed: new, accepted, preparing.'
        )

    # Refund wallet if paid
    if order.payment_status == Order.PaymentStatus.PAID and order.payment_method == Order.PaymentMethod.WALLET:
        order.customer.wallet_balance += order.total_amount
        order.customer.save(update_fields=['wallet_balance'])
        WalletTransaction.objects.create(
            user=order.customer,
            type=WalletTransaction.Type.CREDIT,
            amount=order.total_amount,
            reason=WalletTransaction.Reason.REFUND,
            balance_after=order.customer.wallet_balance,
            reference_id=str(order.id),
            reference_type='order_cancel',
        )

    # Restore points
    if order.points_used > 0:
        order.customer.loyalty_points += order.points_used
        order.customer.save(update_fields=['loyalty_points'])
        PointsTransaction.objects.create(
            user=order.customer,
            transaction_type='bonus',  # refund as bonus credit
            points=order.points_used,
            balance_after=order.customer.loyalty_points,
            description=f'Refund for cancelled order {order.order_number}',
            order=order,
        )

    # Restore stock
    for item in order.items.all():
        if item.product_id:
            Product.objects.filter(pk=item.product_id).update(
                quantity_in_stock=Product.objects.get(pk=item.product_id).quantity_in_stock + int(item.quantity)
            )

    order.cancellation_reason = reason
    order.cancelled_by = by_user
    order.update_status(Order.Status.CANCELLED, user=by_user)
    return order
