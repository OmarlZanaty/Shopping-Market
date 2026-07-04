from django.db import models
from django.conf import settings


class ProductRecommendation(models.Model):
    """
    Pre-computed per-user product recommendations.
    Populated nightly by the Celery task in tasks.py.
    """

    class Source(models.TextChoices):
        COLLABORATIVE = 'collab', 'Collaborative Filtering'
        FREQUENCY = 'frequency', 'Purchase Frequency'
        TRENDING = 'trending', 'Trending in Store'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='product_recommendations',
    )
    product = models.ForeignKey(
        'products.Product', on_delete=models.CASCADE,
        related_name='recommendations',
    )
    score = models.FloatField(default=0.0, help_text='Higher = more relevant')
    source = models.CharField(max_length=20, choices=Source.choices)
    computed_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'product')
        ordering = ['-score']
        indexes = [
            models.Index(fields=['user', '-score']),
            models.Index(fields=['computed_at']),
        ]

    def __str__(self):
        return f'{self.user} → {self.product} ({self.score:.2f})'


class TrendingProduct(models.Model):
    """
    Store-level trending products (no user needed).
    Updated hourly. Used as fallback when a new user has no history.
    """
    product = models.ForeignKey(
        'products.Product', on_delete=models.CASCADE,
        related_name='trending_entries',
    )
    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='trending_products',
    )
    order_count_7d = models.PositiveIntegerField(default=0)
    score = models.FloatField(default=0.0)
    computed_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('product', 'store')
        ordering = ['-score']
        indexes = [
            models.Index(fields=['store', '-score']),
        ]
