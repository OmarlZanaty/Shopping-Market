from django.db import models
from django.utils.translation import gettext_lazy as _


class Promotion(models.Model):
    class DiscountType(models.TextChoices):
        PERCENTAGE = 'percentage', _('Percentage')
        FIXED = 'fixed', _('Fixed Amount')

    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='promotions',
    )

    name_ar = models.CharField(max_length=200)
    name_en = models.CharField(max_length=200)
    code = models.CharField(max_length=50, unique=True, null=True, blank=True)

    discount_type = models.CharField(max_length=20, choices=DiscountType.choices)
    discount_value = models.DecimalField(max_digits=10, decimal_places=2)
    min_order_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    max_discount_amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    usage_limit = models.PositiveIntegerField(null=True, blank=True)
    used_count = models.PositiveIntegerField(default=0)
    per_user_limit = models.PositiveIntegerField(null=True, blank=True)

    start_at = models.DateTimeField()
    end_at = models.DateTimeField()

    applicable_categories = models.JSONField(default=list, blank=True)  # list of category IDs

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['store', 'is_active']),
            models.Index(fields=['code']),
            models.Index(fields=['start_at', 'end_at']),
        ]

    def __str__(self):
        return f'{self.name_en} ({self.code or "no-code"})'

    @property
    def is_currently_valid(self):
        from django.utils import timezone
        now = timezone.now()
        if not self.is_active:
            return False
        if self.start_at > now or self.end_at < now:
            return False
        if self.usage_limit and self.used_count >= self.usage_limit:
            return False
        return True

    def calculate_discount(self, subtotal, category_ids=None):
        if subtotal < self.min_order_amount:
            return 0
        if self.applicable_categories and category_ids:
            if not set(category_ids) & set(self.applicable_categories):
                return 0
        if self.discount_type == self.DiscountType.PERCENTAGE:
            discount = subtotal * (self.discount_value / 100)
        else:
            discount = self.discount_value
        if self.max_discount_amount:
            discount = min(discount, self.max_discount_amount)
        return min(discount, subtotal)


class PromotionUsage(models.Model):
    """Audit log for promo applications — supports per-user limits."""
    promotion = models.ForeignKey(Promotion, on_delete=models.CASCADE, related_name='usages')
    user = models.ForeignKey('users.User', on_delete=models.CASCADE, related_name='promo_usages')
    order = models.ForeignKey('orders.Order', on_delete=models.CASCADE)
    discount_applied = models.DecimalField(max_digits=10, decimal_places=2)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['promotion', 'user']),
        ]


class DeliveryFee(models.Model):
    """Per-zone delivery fee. Multiple zones per branch supported."""
    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='delivery_fees',
    )
    branch = models.ForeignKey(
        'branches.Branch', on_delete=models.CASCADE,
        related_name='delivery_fees',
    )

    zone_name = models.CharField(max_length=100)
    fee = models.DecimalField(max_digits=10, decimal_places=2)

    free_delivery_above = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    peak_hour_surcharge = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    peak_start_time = models.TimeField(null=True, blank=True)
    peak_end_time = models.TimeField(null=True, blank=True)

    # GeoJSON-ish polygon — list of {lat, lng} points
    zone_coordinates = models.JSONField(default=list, blank=True)

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['store', 'branch', 'zone_name']
        indexes = [
            models.Index(fields=['store', 'branch', 'is_active']),
        ]

    def __str__(self):
        return f'{self.zone_name} @ {self.branch} ({self.fee} EGP)'
