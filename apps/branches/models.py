from django.db import models
from django.utils.translation import gettext_lazy as _


class Branch(models.Model):
    # Scope
    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='branches',
    )

    # Identity
    name = models.CharField(max_length=200)
    name_ar = models.CharField(max_length=200)
    name_en = models.CharField(max_length=200, blank=True)

    address = models.TextField()
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    phone = models.CharField(max_length=20)

    manager = models.ForeignKey(
        'users.User', null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name='managed_branches',
        limit_choices_to={'role__in': ['branch_manager', 'admin']},
    )

    is_active = models.BooleanField(default=True)

    delivery_radius_km = models.DecimalField(max_digits=5, decimal_places=2, default=10)
    delivery_fee = models.DecimalField(max_digits=8, decimal_places=2, default=15)

    # Operating hours: simple legacy + structured JSON
    opening_time = models.TimeField(null=True, blank=True)
    closing_time = models.TimeField(null=True, blank=True)
    operating_hours = models.JSONField(
        default=dict, blank=True,
        help_text='{"open":"09:00","close":"23:00","days":[1,2,3,4,5,6,7]}',
    )

    # Seasonal / coastal branch toggle
    is_coastal = models.BooleanField(default=False)
    coastal_start_date = models.DateField(null=True, blank=True)
    coastal_end_date = models.DateField(null=True, blank=True)

    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = 'Branches'
        ordering = ['store', 'sort_order', 'name']
        indexes = [
            models.Index(fields=['store', 'is_active']),
        ]

    def __str__(self):
        return self.name
