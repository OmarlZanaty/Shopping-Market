from django.db import models
from django.conf import settings


class PaymobTransaction(models.Model):
    """Tracks every Paymob payment attempt (order creation + payment key generation)."""

    class TransactionType(models.TextChoices):
        ORDER_PAYMENT = 'order_payment', 'Order Payment'
        ADJUSTMENT_TOP_UP = 'adjustment_top_up', 'Price Adjustment Top-Up'

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PAID = 'paid', 'Paid'
        FAILED = 'failed', 'Failed'
        VOIDED = 'voided', 'Voided'
        REFUNDED = 'refunded', 'Refunded'

    order = models.ForeignKey(
        'orders.Order', on_delete=models.CASCADE,
        related_name='paymob_transactions',
    )
    adjustment = models.ForeignKey(
        'orders.OrderAdjustment', on_delete=models.SET_NULL,
        null=True, blank=True, related_name='paymob_transactions',
        help_text='Set when this payment is for an adjustment top-up.',
    )
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name='paymob_transactions',
    )

    transaction_type = models.CharField(
        max_length=30, choices=TransactionType.choices,
        default=TransactionType.ORDER_PAYMENT,
    )
    status = models.CharField(
        max_length=20, choices=Status.choices,
        default=Status.PENDING,
    )

    # Amounts in EGP (stored as decimal) and in piasters (×100 for Paymob)
    amount_egp = models.DecimalField(max_digits=10, decimal_places=2)
    amount_cents = models.PositiveBigIntegerField()

    # Paymob IDs — populated after successful API calls
    paymob_order_id = models.CharField(max_length=200, blank=True)
    paymob_payment_key = models.CharField(max_length=500, blank=True)
    paymob_transaction_id = models.CharField(max_length=200, blank=True,
        help_text='Filled in by the Paymob webhook on payment success.')

    # Webhook callback data (raw JSON for audit)
    webhook_data = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['order', '-created_at']),
            models.Index(fields=['status']),
            models.Index(fields=['paymob_transaction_id']),
        ]

    def __str__(self):
        return f'PaymobTx #{self.id} — {self.order} — {self.amount_egp} EGP [{self.status}]'
