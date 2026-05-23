"""
Multi-store root entity. Every scoped entity (product, category, branch, banner,
promotion, delivery-fee, order, staff user) carries a FK to Store. Customers do
not — they have one global account that works across all stores.
"""
from django.db import models
from django.utils.translation import gettext_lazy as _


class Store(models.Model):
    class StoreType(models.TextChoices):
        SUPERMARKET = 'supermarket', _('Supermarket')
        PHARMACY = 'pharmacy', _('Pharmacy')
        ELECTRONICS = 'electronics', _('Electronics')
        BAKERY = 'bakery', _('Bakery')
        RESTAURANT = 'restaurant', _('Restaurant')
        OTHER = 'other', _('Other')

    name_ar = models.CharField(max_length=100)
    name_en = models.CharField(max_length=100)
    type = models.CharField(max_length=20, choices=StoreType.choices)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)
    logo_url = models.URLField(max_length=500, blank=True)
    cover_image_url = models.URLField(max_length=500, blank=True)
    primary_color_hex = models.CharField(max_length=7, default='#FF6B35')
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    min_order_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['sort_order', 'name_en']
        indexes = [
            models.Index(fields=['is_active', 'sort_order']),
        ]

    def __str__(self):
        return f'{self.name_en} [{self.type}]'
