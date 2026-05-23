from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from django.utils import timezone

from .models import Promotion, DeliveryFee
from .serializers import PromotionSerializer, DeliveryFeeSerializer
from apps.core.permissions import IsAnyAdmin, IsAdminWriteOrSupportRead
from apps.core.scoping import scope_to_user, enforce_store_id_on_create
from apps.core.responses import ok, fail


# ── Customer-facing promo validation

class PromotionValidateView(APIView):
    """
    Customer types a promo code at checkout. Body: { code, store_id, subtotal, category_ids: [] }.
    Returns either { valid: true, discount_amount } or { valid: false, reason }.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        code = (request.data.get('code') or '').strip().upper()
        store_id = request.data.get('store_id')
        try:
            subtotal = float(request.data.get('subtotal', 0))
        except (TypeError, ValueError):
            return fail('Invalid subtotal', status_code=400)
        category_ids = request.data.get('category_ids') or []

        if not code:
            return fail('Promo code required', status_code=400)

        try:
            promo = Promotion.objects.get(code__iexact=code, store_id=store_id)
        except Promotion.DoesNotExist:
            return ok({'valid': False, 'reason': 'Code not found'})

        if not promo.is_currently_valid:
            return ok({'valid': False, 'reason': 'Code expired or limit reached'})

        # Per-user limit check
        if promo.per_user_limit:
            used = promo.usages.filter(user=request.user).count()
            if used >= promo.per_user_limit:
                return ok({'valid': False, 'reason': 'Per-user limit reached'})

        discount = float(promo.calculate_discount(subtotal, category_ids))
        if discount <= 0:
            return ok({'valid': False, 'reason': 'Not eligible — check min_order_amount or categories'})

        return ok({
            'valid': True,
            'discount_amount': round(discount, 2),
            'promotion_id': promo.id,
            'name_ar': promo.name_ar,
            'name_en': promo.name_en,
        })


# ── Admin CRUD (store-scoped)

class AdminPromotionListCreateView(generics.ListCreateAPIView):
    serializer_class = PromotionSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(Promotion.objects.all(), self.request.user)

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)


class AdminPromotionDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = PromotionSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(Promotion.objects.all(), self.request.user)


class AdminDeliveryFeeListCreateView(generics.ListCreateAPIView):
    serializer_class = DeliveryFeeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(DeliveryFee.objects.all(), self.request.user)

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)


class AdminDeliveryFeeDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = DeliveryFeeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(DeliveryFee.objects.all(), self.request.user)
