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

    @property
    def has_zones(self):
        """Zones override delivery_radius_km. A branch with none keeps the
        circle, so adding this feature changes nothing until someone draws."""
        return self.delivery_zones.filter(is_active=True).exists()


class DeliveryZone(models.Model):
    """An area a branch delivers to, as a drawn polygon.

    Replaces delivery_radius_km's circle, which could not follow a river, a
    ring road, or the edge of a district. Coverage only — no per-zone pricing;
    fee and minimum still come from the branch.

    Geometry is GeoJSON (Polygon or MultiPolygon, [lng, lat] order) in a plain
    JSONField: this database has no PostGIS, and containment is answered in
    Python by apps.branches.geo. `bbox` is maintained on save purely as a cheap
    prefilter so the exact test runs only for zones the point could be in.
    """

    class Source(models.TextChoices):
        DRAWN = 'drawn', 'Drawn on the map'
        CIRCLE = 'circle', 'Converted from delivery radius'
        IMPORTED = 'imported', 'Imported boundary'

    branch = models.ForeignKey(
        Branch, on_delete=models.CASCADE, related_name='delivery_zones',
    )

    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120, blank=True)

    geometry = models.JSONField(help_text='GeoJSON Polygon or MultiPolygon, [lng, lat]')
    bbox = models.JSONField(
        null=True, blank=True,
        help_text='[min_lng, min_lat, max_lng, max_lat] — derived, do not edit',
    )

    source = models.CharField(max_length=20, choices=Source.choices, default=Source.DRAWN)
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['branch', 'name_ar']
        indexes = [
            models.Index(fields=['branch', 'is_active']),
        ]

    def __str__(self):
        return f'{self.name_ar} ({self.branch.name})'

    def save(self, *args, **kwargs):
        from .geo import bbox_of
        self.bbox = bbox_of(self.geometry)
        super().save(*args, **kwargs)

    def contains(self, lat, lng):
        from .geo import contains_point, in_bbox
        if not in_bbox(float(lat), float(lng), self.bbox):
            return False
        return contains_point(self.geometry, lat, lng)
