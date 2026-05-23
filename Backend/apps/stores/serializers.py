from rest_framework import serializers
from .models import Store


class StoreCardSerializer(serializers.ModelSerializer):
    """Light payload for the customer-app store grid."""

    class Meta:
        model = Store
        fields = [
            'id', 'name_ar', 'name_en', 'type',
            'logo_url', 'cover_image_url', 'primary_color_hex',
            'min_order_amount', 'sort_order',
        ]


class StoreDetailSerializer(serializers.ModelSerializer):
    nearest_branch = serializers.SerializerMethodField()

    class Meta:
        model = Store
        fields = [
            'id', 'name_ar', 'name_en', 'type',
            'description_ar', 'description_en',
            'logo_url', 'cover_image_url', 'primary_color_hex',
            'min_order_amount', 'sort_order', 'is_active',
            'nearest_branch',
        ]

    def get_nearest_branch(self, obj):
        req = self.context.get('request')
        if not req:
            return None
        lat = req.query_params.get('lat')
        lng = req.query_params.get('lng')
        if not (lat and lng):
            return None
        try:
            lat, lng = float(lat), float(lng)
        except (TypeError, ValueError):
            return None
        from apps.branches.models import Branch
        from math import sqrt
        branches = list(Branch.objects.filter(store_id=obj.id, is_active=True))
        if not branches:
            return None
        nearest = min(
            branches,
            key=lambda b: sqrt((float(b.latitude) - lat) ** 2 + (float(b.longitude) - lng) ** 2)
        )
        return {
            'id': nearest.id,
            'name_ar': nearest.name_ar,
            'name_en': getattr(nearest, 'name', '') or getattr(nearest, 'name_en', ''),
            'address': nearest.address,
            'lat': str(nearest.latitude),
            'lng': str(nearest.longitude),
            'delivery_radius_km': str(nearest.delivery_radius_km),
        }


class StoreAdminSerializer(serializers.ModelSerializer):
    branch_count = serializers.SerializerMethodField()
    product_count = serializers.SerializerMethodField()
    order_count = serializers.SerializerMethodField()

    class Meta:
        model = Store
        fields = '__all__'

    def get_branch_count(self, obj):
        return obj.branches.count() if hasattr(obj, 'branches') else 0

    def get_product_count(self, obj):
        return obj.products.count() if hasattr(obj, 'products') else 0

    def get_order_count(self, obj):
        return obj.orders.count() if hasattr(obj, 'orders') else 0


class MultistoreSettingsSerializer(serializers.Serializer):
    multistore_enabled = serializers.BooleanField()
    default_store_id = serializers.IntegerField(allow_null=True, required=False)
