"""
AI Recommendation Engine
========================

Two complementary signals, merged by weighted average:

1. Collaborative Filtering ("customers like you also bought"):
   - For each product the user has ordered, find all other orders containing
     that product.
   - Collect every OTHER product in those co-orders and count occurrences.
   - Normalize by the number of co-orders (Jaccard-like overlap).

2. Purchase Frequency ("you usually order this"):
   - Count how many times THIS user ordered each product.
   - Recency-decay: orders in the last 30 days count double.

Merged score  =  0.5 × collab_score  +  0.5 × freq_score  (both 0-1 normalised)

Results are persisted in ProductRecommendation (upsert). The task clears stale
rows (products no longer in stock, already excluded from results) afterwards.
"""

import logging
from collections import defaultdict
from datetime import timedelta

from django.db.models import Count, Q
from django.utils import timezone

logger = logging.getLogger(__name__)


def _safe_div(n, d):
    return n / d if d else 0.0


def compute_recommendations_for_user(user) -> int:
    """
    Compute and persist recommendations for a single user.
    Returns the number of rows upserted.
    """
    from apps.orders.models import Order, OrderItem
    from apps.products.models import Product
    from .models import ProductRecommendation

    # ── 1. User's ordered products ────────────────────────────────────────────
    completed = [Order.Status.DELIVERED, Order.Status.OUT_FOR_DELIVERY]
    user_order_ids = list(
        Order.objects.filter(customer=user, status__in=completed)
        .values_list('id', flat=True)
    )
    if not user_order_ids:
        return _trending_fallback(user)

    user_product_ids = set(
        OrderItem.objects.filter(order_id__in=user_order_ids)
        .values_list('product_id', flat=True)
    )
    if not user_product_ids:
        return _trending_fallback(user)

    # ── 2. Collaborative filtering ────────────────────────────────────────────
    # Orders from ANY customer that contain ≥1 of the user's products
    co_order_ids = list(
        OrderItem.objects.filter(
            product_id__in=user_product_ids,
            order__status__in=completed,
        )
        .exclude(order_id__in=user_order_ids)
        .values_list('order_id', flat=True)
        .distinct()
    )

    collab_counts: dict[int, int] = defaultdict(int)
    if co_order_ids:
        co_items = OrderItem.objects.filter(
            order_id__in=co_order_ids,
        ).exclude(product_id__in=user_product_ids).values_list('product_id', flat=True)
        for pid in co_items:
            collab_counts[pid] += 1

    collab_max = max(collab_counts.values()) if collab_counts else 1

    # ── 3. Purchase frequency ─────────────────────────────────────────────────
    now = timezone.now()
    cutoff_recent = now - timedelta(days=30)

    freq_counts: dict[int, float] = defaultdict(float)
    for item in OrderItem.objects.filter(order_id__in=user_order_ids).select_related('order'):
        weight = 2.0 if item.order.created_at >= cutoff_recent else 1.0
        freq_counts[item.product_id] += weight

    freq_max = max(freq_counts.values()) if freq_counts else 1

    # ── 4. Merge & normalise ──────────────────────────────────────────────────
    candidate_ids = set(collab_counts.keys()) | set(freq_counts.keys())
    # Remove products user already ordered (keep repeat-purchase ones from freq)
    # but exclude products currently out of stock
    in_stock = set(
        Product.objects.filter(
            id__in=candidate_ids,
            is_available=True,
        ).values_list('id', flat=True)
    )
    candidate_ids &= in_stock

    rows = []
    for pid in candidate_ids:
        c_score = _safe_div(collab_counts.get(pid, 0), collab_max)
        f_score = _safe_div(freq_counts.get(pid, 0), freq_max)
        merged = 0.5 * c_score + 0.5 * f_score

        source = (
            ProductRecommendation.Source.COLLABORATIVE if c_score >= f_score
            else ProductRecommendation.Source.FREQUENCY
        )
        rows.append(ProductRecommendation(
            user=user, product_id=pid, score=round(merged, 4), source=source,
        ))

    # Upsert
    ProductRecommendation.objects.bulk_create(
        rows,
        update_conflicts=True,
        unique_fields=['user', 'product'],
        update_fields=['score', 'source', 'computed_at'],
    )
    # Prune rows for products no longer available
    ProductRecommendation.objects.filter(
        user=user,
    ).exclude(product_id__in=in_stock).delete()

    logger.debug('[AI] %s: %d recommendations computed', user.id, len(rows))
    return len(rows)


def _trending_fallback(user) -> int:
    """
    New user with no order history — copy trending products as recommendations.
    """
    from .models import ProductRecommendation, TrendingProduct

    trending = list(
        TrendingProduct.objects.order_by('-score')[:30]
    )
    if not trending:
        return 0

    rows = [
        ProductRecommendation(
            user=user,
            product_id=t.product_id,
            score=t.score,
            source=ProductRecommendation.Source.TRENDING,
        )
        for t in trending
    ]
    ProductRecommendation.objects.bulk_create(
        rows,
        update_conflicts=True,
        unique_fields=['user', 'product'],
        update_fields=['score', 'source', 'computed_at'],
    )
    return len(rows)


def compute_trending(store_id=None):
    """
    Compute trending products for each store based on order volume in the last 7
    days. Called by the Celery task.
    """
    from apps.orders.models import Order, OrderItem
    from apps.stores.models import Store
    from .models import TrendingProduct

    cutoff = timezone.now() - timedelta(days=7)
    store_qs = Store.objects.all()
    if store_id:
        store_qs = store_qs.filter(id=store_id)

    total_upserted = 0
    for store in store_qs:
        order_ids = list(
            Order.objects.filter(
                store=store, status=Order.Status.DELIVERED,
                created_at__gte=cutoff,
            ).values_list('id', flat=True)
        )
        if not order_ids:
            continue

        counts = (
            OrderItem.objects.filter(order_id__in=order_ids)
            .values('product_id')
            .annotate(cnt=Count('id'))
            .order_by('-cnt')[:50]
        )
        max_cnt = counts[0]['cnt'] if counts else 1

        rows = []
        for row in counts:
            rows.append(TrendingProduct(
                product_id=row['product_id'],
                store=store,
                order_count_7d=row['cnt'],
                score=round(row['cnt'] / max_cnt, 4),
            ))
        TrendingProduct.objects.bulk_create(
            rows,
            update_conflicts=True,
            unique_fields=['product', 'store'],
            update_fields=['order_count_7d', 'score', 'computed_at'],
        )
        total_upserted += len(rows)

    logger.info('[AI] trending computed: %d product-store pairs', total_upserted)
    return total_upserted
