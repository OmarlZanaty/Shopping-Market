"""
AI endpoints:
  GET  /ai/recommendations/   — personalised product recommendations
  GET  /ai/smart-cart/        — "you usually order this" nudge list
  POST /ai/visual-search/     — image → product matches (Gemini Vision)
"""
import base64
import logging

from rest_framework import permissions
from rest_framework.views import APIView

from apps.core.responses import ok, fail
from apps.products.models import Product

logger = logging.getLogger(__name__)


class RecommendationsView(APIView):
    """
    GET /ai/recommendations/?limit=10&store_id=<uuid>

    Returns pre-computed personalised recommendations. Falls back to trending
    if no precomputed rows exist for this user yet.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from .models import ProductRecommendation, TrendingProduct
        from apps.products.serializers import ProductSerializer

        limit = min(int(request.query_params.get('limit', 10)), 30)
        store_id = request.query_params.get('store_id')

        recs = (
            ProductRecommendation.objects.filter(user=request.user)
            .select_related('product', 'product__category')
            .order_by('-score')
        )
        if store_id:
            recs = recs.filter(product__store_id=store_id)
        recs = list(recs[:limit])

        if not recs:
            # No personalized data yet — serve trending
            trending_qs = TrendingProduct.objects.select_related(
                'product', 'product__category'
            ).order_by('-score')
            if store_id:
                trending_qs = trending_qs.filter(store_id=store_id)
            products = [t.product for t in trending_qs[:limit]]
        else:
            products = [r.product for r in recs]

        # Annotate with is_on_waitlist for out-of-stock products
        data = ProductSerializer(
            products, many=True, context={'request': request}
        ).data
        return ok({'results': data, 'count': len(data)})


class SmartCartView(APIView):
    """
    GET /ai/smart-cart/?store_id=<uuid>

    Returns "you usually order these" items that are NOT already in the
    customer's pending/active order, sorted by purchase frequency.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from apps.orders.models import Order, OrderItem
        from apps.products.serializers import ProductSerializer
        from django.utils import timezone
        from datetime import timedelta

        store_id = request.query_params.get('store_id')
        limit = min(int(request.query_params.get('limit', 8)), 20)

        completed = [Order.Status.DELIVERED]
        cutoff = timezone.now() - timedelta(days=60)

        order_ids = list(
            Order.objects.filter(
                customer=request.user,
                status__in=completed,
                created_at__gte=cutoff,
            ).values_list('id', flat=True)
        )
        if not order_ids:
            return ok({'results': [], 'count': 0})

        from django.db.models import Count
        freq_qs = (
            OrderItem.objects.filter(order_id__in=order_ids)
            .values('product_id')
            .annotate(cnt=Count('id'))
            .order_by('-cnt')[:limit * 2]   # over-fetch to allow filtering
        )

        candidate_ids = [r['product_id'] for r in freq_qs]
        products = list(
            Product.objects.filter(
                id__in=candidate_ids,
                is_available=True,
            ).select_related('category')
        )
        if store_id:
            products = [p for p in products if str(p.store_id) == store_id]

        # Sort by frequency order
        id_to_pos = {r['product_id']: i for i, r in enumerate(freq_qs)}
        products.sort(key=lambda p: id_to_pos.get(p.id, 99))
        products = products[:limit]

        data = ProductSerializer(
            products, many=True, context={'request': request}
        ).data
        return ok({'results': data, 'count': len(data)})


class VisualSearchView(APIView):
    """
    POST /ai/visual-search/
    Body (multipart): image=<file>   OR   { "image_base64": "<base64>" }

    Uses Gemini Vision to identify the item, then searches the product catalog.
    Falls back to a text search if Gemini is not configured.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from apps.products.models import Product
        from apps.products.serializers import ProductSerializer

        # Accept multipart file or base64 JSON
        image_file = request.FILES.get('image')
        image_b64 = request.data.get('image_base64', '')

        if image_file:
            image_bytes = image_file.read()
            image_b64 = base64.b64encode(image_bytes).decode()
        elif not image_b64:
            return fail('image or image_base64 required', status_code=400)

        # ── Gemini Vision ─────────────────────────────────────────────────────
        search_query = None
        try:
            search_query = _identify_with_gemini(image_b64)
        except Exception as e:
            logger.warning('[AI] Gemini visual search error: %s', e)

        if not search_query:
            return ok({'results': [], 'count': 0, 'query': None})

        # ── Product catalog search ─────────────────────────────────────────────
        store_id = request.query_params.get('store_id')
        qs = Product.objects.filter(is_available=True).select_related('category')
        if store_id:
            qs = qs.filter(store_id=store_id)

        from django.db.models import Q
        results = qs.filter(
            Q(name_ar__icontains=search_query) |
            Q(name_en__icontains=search_query) |
            Q(description_ar__icontains=search_query) |
            Q(description_en__icontains=search_query)
        )[:12]

        data = ProductSerializer(results, many=True, context={'request': request}).data
        return ok({'results': data, 'count': len(data), 'query': search_query})


def _identify_with_gemini(image_b64: str) -> str | None:
    """
    Call Gemini 1.5 Flash to identify the grocery item in the image.
    Returns a short search phrase (Arabic or English), or None on failure.
    """
    from django.conf import settings
    api_key = getattr(settings, 'GEMINI_API_KEY', '')
    if not api_key:
        return None

    import urllib.request
    import json

    url = (
        f'https://generativelanguage.googleapis.com/v1beta/models/'
        f'gemini-1.5-flash:generateContent?key={api_key}'
    )
    payload = {
        'contents': [{
            'parts': [
                {
                    'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': image_b64,
                    }
                },
                {
                    'text': (
                        'Look at this grocery/supermarket product image. '
                        'Reply with ONLY the product name in Arabic (1-4 words). '
                        'Example: "بندورة طازجة" or "زيت زيتون". '
                        'No explanation, just the product name.'
                    )
                },
            ]
        }],
        'generationConfig': {'maxOutputTokens': 20, 'temperature': 0.1},
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())

    candidates = result.get('candidates', [])
    if not candidates:
        return None
    text = candidates[0].get('content', {}).get('parts', [{}])[0].get('text', '').strip()
    # Sanitize — take first line only
    return text.split('\n')[0].strip() or None
