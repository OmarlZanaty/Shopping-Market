from django.db import models
from django.db import transaction
from django.utils.translation import gettext_lazy as _
from django.utils import timezone
from django.conf import settings
import uuid


def generate_order_number(store_id=None):
    """
    Race-safe order_number generator. Spec format: ORD-YYYYMMDD-NNN
    Sequential per calendar day. Uses SELECT ... FOR UPDATE inside an atomic
    block so concurrent requests cannot produce duplicates.

    Note: this is called inside Order.save() under a transaction, so the lock
    is released as soon as the row is inserted.
    """
    today = timezone.now().date()
    date_str = today.strftime('%Y%m%d')
    prefix = f'ORD-{date_str}-'
    with transaction.atomic():
        # Acquire row-level locks on today's orders to make the count atomic.
        latest = (
            Order.objects
            .select_for_update(skip_locked=False)
            .filter(order_number__startswith=prefix)
            .order_by('-order_number')
            .values_list('order_number', flat=True)
            .first()
        )
        if latest:
            try:
                seq = int(latest.split('-')[-1]) + 1
            except (ValueError, IndexError):
                seq = Order.objects.filter(order_number__startswith=prefix).count() + 1
        else:
            seq = 1
        return f'{prefix}{seq:03d}'


class Order(models.Model):
    class Status(models.TextChoices):
        NEW = 'new', _('New')
        ACCEPTED = 'accepted', _('Accepted')
        PREPARING = 'preparing', _('Preparing')
        OUT_FOR_DELIVERY = 'out_for_delivery', _('Out for Delivery')
        DELIVERED = 'delivered', _('Delivered')
        CANCELLED = 'cancelled', _('Cancelled')

    class PaymentMethod(models.TextChoices):
        CASH = 'cash', _('Cash on Delivery')
        ONLINE = 'online', _('Online (Card/Visa)')
        POS = 'pos', _('POS on Delivery')
        WALLET = 'wallet', _('Wallet')
        POINTS = 'points', _('Loyalty Points')
        MIXED = 'mixed', _('Mixed')

    class PaymentStatus(models.TextChoices):
        PENDING = 'pending', _('Pending')
        PAID = 'paid', _('Paid')
        REFUNDED = 'refunded', _('Refunded')
        PARTIAL = 'partial_refund', _('Partial Refund')

    class ClosedBy(models.TextChoices):
        CUSTOMER = 'customer', _('Customer')
        DRIVER = 'driver', _('Driver Auto-close')
        ADMIN = 'admin', _('Admin')

    # Identity
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    order_number = models.CharField(
        max_length=30, unique=True, db_index=True,
        help_text='ORD-YYYYMMDD-NNN, sequential per day',
    )
    # Legacy alias retained for backward compatibility with existing code
    order_id = models.CharField(max_length=30, unique=True, db_index=True, blank=True)

    # Scope
    store = models.ForeignKey(
        'stores.Store', on_delete=models.PROTECT,
        related_name='orders',
    )

    # People
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name='customer_orders',
    )
    preparer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='preparer_orders',
        limit_choices_to={'role': 'preparer'},
    )
    driver = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='driver_orders',
        limit_choices_to={'role': 'driver'},
    )
    branch = models.ForeignKey(
        'branches.Branch', on_delete=models.PROTECT,
        null=True, related_name='orders',
    )
    address = models.ForeignKey(
        'users.Address', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='orders',
    )

    # Status
    status = models.CharField(
        max_length=30, choices=Status.choices,
        default=Status.NEW, db_index=True,
    )

    # Delivery snapshot (denormalized at creation)
    delivery_address = models.TextField()
    building_number = models.CharField(max_length=20)
    floor_number = models.CharField(max_length=10)
    apartment_number = models.CharField(max_length=10)
    landmark = models.CharField(max_length=200, blank=True)
    delivery_latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True)
    delivery_longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True)
    delivery_name = models.CharField(max_length=150)
    delivery_phone = models.CharField(max_length=20)

    # Financials
    subtotal = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=15)
    tax_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    discount_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    points_used = models.PositiveIntegerField(default=0)
    points_value = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    points_value_used = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_savings = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    amount_collected = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Payment
    payment_method = models.CharField(
        max_length=20, choices=PaymentMethod.choices, default=PaymentMethod.CASH,
    )
    payment_status = models.CharField(
        max_length=20, choices=PaymentStatus.choices, default=PaymentStatus.PENDING,
    )
    paymob_order_id = models.CharField(max_length=200, blank=True)

    # Notes
    customer_notes = models.TextField(blank=True)
    cancellation_reason = models.TextField(blank=True)

    # Close tracking
    closed_by = models.CharField(max_length=20, choices=ClosedBy.choices, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='cancelled_orders',
    )
    driver_proof_image = models.ImageField(upload_to='delivery_proofs/', null=True, blank=True)
    delivery_photo_url = models.URLField(max_length=500, blank=True)
    closed_by_driver_at = models.DateTimeField(null=True, blank=True)

    # Promotion applied
    promotion_code = models.CharField(max_length=50, blank=True)
    promotion_discount = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    preparing_at = models.DateTimeField(null=True, blank=True)
    out_for_delivery_at = models.DateTimeField(null=True, blank=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Loyalty
    points_earned = models.PositiveIntegerField(default=0)
    points_awarded = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['order_number']),
            models.Index(fields=['status']),
            models.Index(fields=['customer', 'status']),
            models.Index(fields=['driver', 'status']),
            models.Index(fields=['preparer', 'status']),
            models.Index(fields=['branch', 'status']),
            models.Index(fields=['store', 'status']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f'{self.order_number} - {self.customer.full_name} [{self.status}]'

    def save(self, *args, **kwargs):
        if not self.order_number:
            self.order_number = generate_order_number(self.store_id)
        if not self.order_id:
            self.order_id = self.order_number  # back-compat alias
        super().save(*args, **kwargs)

    def calculate_totals(self):
        items = self.items.all()
        self.subtotal = sum((item.line_total for item in items), 0)
        self.total_savings = sum((item.savings for item in items), 0)
        self.total_amount = max(
            0,
            (self.subtotal + self.delivery_fee + self.tax_amount
             - self.discount_amount - self.points_value - self.promotion_discount)
        )
        self.save(update_fields=['subtotal', 'total_amount', 'total_savings', 'updated_at'])

    def update_status(self, new_status, user=None):
        self.status = new_status
        now = timezone.now()
        if new_status == self.Status.ACCEPTED:
            self.accepted_at = now
        elif new_status == self.Status.PREPARING:
            self.preparing_at = now
        elif new_status == self.Status.OUT_FOR_DELIVERY:
            self.out_for_delivery_at = now
        elif new_status == self.Status.DELIVERED:
            self.delivered_at = now
            self.payment_status = self.PaymentStatus.PAID
            if user:
                self.closed_by = (
                    self.ClosedBy.CUSTOMER if user == self.customer else self.ClosedBy.DRIVER
                )
        elif new_status == self.Status.CANCELLED:
            self.cancelled_at = now
        self.save()
        self._notify_status_change()
        self._emit_ws_status_change()

    def _notify_status_change(self):
        from apps.notifications.utils import send_push_notification
        messages = {
            'accepted': ('تم قبول طلبك', 'Your order has been accepted'),
            'preparing': ('يتم تجهيز طلبك', 'Your order is being prepared'),
            'out_for_delivery': ('طلبك في الطريق إليك!', 'Your order is on the way!'),
            'delivered': ('تم تسليم طلبك بنجاح', 'Your order has been delivered!'),
            'cancelled': ('تم إلغاء طلبك', 'Your order was cancelled'),
        }
        if self.status in messages:
            ar, en = messages[self.status]
            send_push_notification(
                user=self.customer,
                title_ar=ar, title_en=en,
                body_ar=f'طلب رقم {self.order_number}',
                body_en=f'Order #{self.order_number}',
                data={'type': 'order_status', 'order_id': str(self.id),
                      'order_number': self.order_number, 'status': self.status},
            )

    def _emit_ws_status_change(self):
        try:
            from channels.layers import get_channel_layer
            from asgiref.sync import async_to_sync
            channel_layer = get_channel_layer()
            if not channel_layer:
                return
            async_to_sync(channel_layer.group_send)(
                f'order_{self.order_number}',
                {
                    'type': 'order_update',
                    'status': self.status,
                    'message_ar': '', 'message_en': '',
                },
            )
            async_to_sync(channel_layer.group_send)(
                'admin_dashboard',
                {
                    'type': 'order_status_changed',
                    'order_id': str(self.id),
                    'order_number': self.order_number,
                    'status': self.status,
                    'store_id': self.store_id,
                },
            )
        except Exception:
            # WS layer optional in some envs; never block status transitions.
            pass

    def award_points(self):
        if self.points_awarded or self.status != self.Status.DELIVERED:
            return
        from apps.notifications.models import AppSettings
        try:
            points_per_egp = int(AppSettings.get('loyalty_earn_rate', '1') or 1)
        except (TypeError, ValueError):
            points_per_egp = 1
        points = int(self.total_amount * points_per_egp)
        if points <= 0:
            return
        self.customer.loyalty_points += points
        self.customer.save(update_fields=['loyalty_points'])
        from apps.users.models import PointsTransaction
        PointsTransaction.objects.create(
            user=self.customer,
            transaction_type='earned',
            points=points,
            balance_after=self.customer.loyalty_points,
            description=f'Points for order {self.order_number}',
            order=self,
        )
        self.points_earned = points
        self.points_awarded = True
        self.save(update_fields=['points_earned', 'points_awarded'])


class OrderItem(models.Model):
    class ItemStatus(models.TextChoices):
        PENDING = 'pending', _('Pending')
        PICKED = 'picked', _('Picked')
        COLLECTED = 'collected', _('Collected')
        UNAVAILABLE = 'unavailable', _('Unavailable')
        SUBSTITUTED = 'substituted', _('Substituted')
        WEIGHT_ADJUSTED = 'weight_adjusted', _('Weight Adjusted')
        PRICE_ADJUSTED = 'price_adjusted', _('Price Adjusted')
        ADDED = 'added', _('Added by Agent')
        REMOVED = 'removed', _('Removed')
        REJECTED = 'rejected', _('Rejected by Customer')

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='items')
    product = models.ForeignKey('products.Product', on_delete=models.PROTECT)
    product_name_ar = models.CharField(max_length=200)
    product_name_en = models.CharField(max_length=200)
    product_barcode = models.CharField(max_length=50, blank=True)

    unit_type = models.CharField(max_length=20, blank=True)
    quantity = models.DecimalField(max_digits=8, decimal_places=3)
    requested_qty = models.DecimalField(max_digits=8, decimal_places=3, default=0)
    actual_qty = models.DecimalField(max_digits=8, decimal_places=3, null=True, blank=True)
    delivered_quantity = models.DecimalField(max_digits=8, decimal_places=3, null=True, blank=True)

    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    final_unit_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    final_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    line_total_snapshot = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    status = models.CharField(max_length=20, choices=ItemStatus.choices, default=ItemStatus.PENDING)
    added_by_agent = models.BooleanField(default=False)
    added_by_driver = models.BooleanField(default=False)  # legacy alias
    customer_approved = models.BooleanField(null=True, blank=True)
    agent_notes = models.TextField(blank=True)
    driver_notes = models.TextField(blank=True)  # legacy alias

    substitute_product = models.ForeignKey(
        'products.Product', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='+',
    )

    # Weight handling
    weight_ordered = models.DecimalField(max_digits=10, decimal_places=3, null=True, blank=True)
    weight_actual = models.DecimalField(max_digits=10, decimal_places=3, null=True, blank=True)
    weight_difference_approved = models.BooleanField(null=True, blank=True)
    weight_variance = models.DecimalField(max_digits=6, decimal_places=3, default=0)
    weight_variance_amount = models.DecimalField(max_digits=8, decimal_places=2, default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']
        indexes = [
            models.Index(fields=['order', 'status']),
        ]

    def __str__(self):
        return f'{self.product_name_en} x{self.quantity}'

    @property
    def line_total(self):
        # Unavailable / removed items don't count toward the order total.
        if self.status in (OrderItem.ItemStatus.UNAVAILABLE,
                            OrderItem.ItemStatus.REMOVED):
            return 0
        price = self.final_unit_price or self.unit_price
        qty = self.delivered_quantity or self.actual_qty or self.quantity
        return price * qty

    @property
    def savings(self):
        try:
            if self.product and self.product.original_price > self.unit_price:
                return (self.product.original_price - self.unit_price) * self.quantity
        except Exception:
            pass
        return 0

    def apply_substitute(self):
        """Replace this line's product with its approved substitute, in place,
        so the order list shows the NEW product and the total uses its price.

        Called when the customer approves a SUBSTITUTE_SUGGESTED adjustment. The
        suggestion step left this item UNAVAILABLE (dropped from the total);
        here we swap in the substitute and mark it SUBSTITUTED so line_total
        counts it again at the new price. No-op swap if no substitute is set."""
        sub = self.substitute_product
        if not sub:
            self.status = OrderItem.ItemStatus.SUBSTITUTED
            self.save(update_fields=['status'])
            return
        self.product = sub
        self.product_name_ar = sub.name_ar
        self.product_name_en = sub.name_en
        self.product_barcode = sub.barcode or ''
        self.unit_type = sub.sell_unit
        self.unit_price = sub.current_price
        self.final_unit_price = sub.current_price
        self.status = OrderItem.ItemStatus.SUBSTITUTED
        self.customer_approved = True
        self.save(update_fields=[
            'product', 'product_name_ar', 'product_name_en', 'product_barcode',
            'unit_type', 'unit_price', 'final_unit_price', 'status',
            'customer_approved',
        ])


class OrderAdjustment(models.Model):
    class AdjustmentType(models.TextChoices):
        PRICE_CHANGE = 'price_change', _('Price Change')
        QUANTITY_CHANGE = 'quantity_change', _('Quantity Change')
        QTY_CHANGE = 'qty_change', _('Quantity Change')  # spec alias
        SUBSTITUTE_SUGGESTED = 'substitute_suggested', _('Substitute Suggested')
        SUBSTITUTE_APPROVED = 'substitute_approved', _('Substitute Approved')
        SUBSTITUTE_REJECTED = 'substitute_rejected', _('Substitute Rejected')
        SUBSTITUTE = 'substitute', _('Product Substituted')  # legacy
        WEIGHT_DIFF_SENT = 'weight_diff_sent', _('Weight Diff Sent')
        WEIGHT_DIFF_APPROVED = 'weight_diff_approved', _('Weight Diff Approved')
        WEIGHT_DIFF_REJECTED = 'weight_diff_rejected', _('Weight Diff Rejected')
        ITEM_ADDED = 'item_added', _('Item Added')
        ITEM_REMOVED = 'item_removed', _('Item Removed')
        BARCODE_SCANNED = 'barcode_scanned', _('Barcode Scanned')
        PHOTO_TAKEN = 'photo_taken', _('Photo Taken')
        DATA_SHARED = 'data_shared', _('Customer Data Shared')
        STATUS_CHANGED = 'status_changed', _('Status Changed')
        CALL_ATTEMPT = 'call_attempt', _('Call Attempt')

    class ApprovalStatus(models.TextChoices):
        PENDING = 'pending', _('Pending')
        APPROVED = 'approved', _('Approved')
        REJECTED = 'rejected', _('Rejected')

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='adjustments')
    order_item = models.ForeignKey(
        OrderItem, on_delete=models.CASCADE,
        null=True, blank=True, related_name='adjustments',
    )
    preparer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, related_name='preparer_adjustments',
    )
    driver = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, related_name='driver_adjustments',
    )
    action_type = models.CharField(max_length=30, choices=AdjustmentType.choices)
    # legacy alias
    adjustment_type = models.CharField(max_length=30, blank=True)

    old_value = models.TextField(blank=True)
    new_value = models.TextField(blank=True)
    reason = models.TextField(blank=True)

    customer_approval_status = models.CharField(
        max_length=20, choices=ApprovalStatus.choices,
        null=True, blank=True,
    )
    customer_approval_at = models.DateTimeField(null=True, blank=True)
    customer_approved = models.BooleanField(null=True, blank=True)  # legacy
    new_total = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    # For the 15-min timeout task
    approval_deadline = models.DateTimeField(null=True, blank=True)
    timeout_task_id = models.CharField(max_length=200, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['order', '-created_at']),
            models.Index(fields=['action_type', '-created_at']),
            models.Index(fields=['preparer', '-created_at']),
        ]

    def save(self, *args, **kwargs):
        # Keep legacy `adjustment_type` field synced for older code paths.
        if self.action_type and not self.adjustment_type:
            self.adjustment_type = self.action_type
        super().save(*args, **kwargs)


class OrderRating(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name='rating')
    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    product_rating = models.PositiveSmallIntegerField(choices=[(i, i) for i in range(1, 6)])
    delivery_rating = models.PositiveSmallIntegerField(choices=[(i, i) for i in range(1, 6)])
    comment = models.TextField(blank=True)
    photo = models.ImageField(upload_to='rating_photos/', null=True, blank=True)
    photo_url = models.URLField(max_length=500, blank=True)
    sentiment = models.CharField(max_length=20, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']


class SmartTimerAutoClose(models.Model):
    """Tracks the 2-hour timer for auto-closing orders."""
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name='timer')
    driver_marked_delivered_at = models.DateTimeField(auto_now_add=True)
    auto_close_scheduled_at = models.DateTimeField()
    is_resolved = models.BooleanField(default=False)

    class Meta:
        ordering = ['-driver_marked_delivered_at']
