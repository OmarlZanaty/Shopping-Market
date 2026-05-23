from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _


class AppSettings(models.Model):
    """Global app settings editable from admin dashboard."""
    key = models.CharField(max_length=100, unique=True)
    value = models.TextField()
    description = models.CharField(max_length=300, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = 'App Settings'

    def __str__(self):
        return self.key

    @classmethod
    def get(cls, key, default=''):
        try:
            return cls.objects.get(key=key).value
        except cls.DoesNotExist:
            return default


class InAppNotification(models.Model):
    class Type(models.TextChoices):
        ORDER_STATUS = 'order_status', _('Order Status')
        PRICE_CHANGE = 'price_change', _('Price Change')
        UNAVAILABLE = 'unavailable', _('Item Unavailable')
        ALTERNATIVE = 'alternative', _('Alternative Suggested')
        WEIGHT_DIFF = 'weight_diff', _('Weight Difference')
        PROMOTION = 'promotion', _('Promotion')
        WAITLIST = 'waitlist', _('Waitlist Restock')
        GENERAL = 'general', _('General')

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE, related_name='notifications',
    )
    title_ar = models.CharField(max_length=200)
    title_en = models.CharField(max_length=200, blank=True)
    body_ar = models.TextField()
    body_en = models.TextField(blank=True)
    type = models.CharField(max_length=30, choices=Type.choices, default=Type.GENERAL)
    data = models.JSONField(default=dict)
    is_read = models.BooleanField(default=False)
    sent_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'is_read']),
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['type', '-created_at']),
        ]
