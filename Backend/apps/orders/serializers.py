from rest_framework import serializers

from .models import Order, OrderItem, OrderAdjustment, OrderRating
from apps.products.models import Product
from apps.users.models import Address


class OrderItemSerializer(serializers.ModelSerializer):
    product_image = serializers.SerializerMethodField()
    line_total = serializers.ReadOnlyField()

    class Meta:
        model = OrderItem
        fields = '__all__'

    def get_product_image(self, obj):
        try:
            if obj.product and obj.product.main_image:
                request = self.context.get('request')
                if request:
                    return request.build_absolute_uri(obj.product.main_image.url)
                return obj.product.image_url_s3 or ''
        except Exception:
            pass
        return ''


class OrderAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderAdjustment
        fields = '__all__'


class OrderRatingSerializer(serializers.ModelSerializer):
    # Spec aliases
    product_quality_rating = serializers.IntegerField(source='product_rating', min_value=1, max_value=5)
    delivery_speed_rating = serializers.IntegerField(source='delivery_rating', min_value=1, max_value=5)

    class Meta:
        model = OrderRating
        fields = ['id', 'order', 'customer', 'product_quality_rating', 'delivery_speed_rating',
                  'product_rating', 'delivery_rating', 'comment', 'photo', 'photo_url',
                  'sentiment', 'created_at', 'updated_at']
        read_only_fields = ['order', 'customer', 'sentiment', 'created_at', 'updated_at',
                            'product_rating', 'delivery_rating']


class OrderSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True, read_only=True)
    adjustments = OrderAdjustmentSerializer(many=True, read_only=True)
    driver_info = serializers.SerializerMethodField()
    preparer_info = serializers.SerializerMethodField()
    customer_info = serializers.SerializerMethodField()
    rating = OrderRatingSerializer(read_only=True)

    class Meta:
        model = Order
        fields = '__all__'

    def get_driver_info(self, obj):
        if obj.driver:
            return {
                'id': str(obj.driver.id),
                'name': obj.driver.full_name,
                'phone': obj.driver.phone,
                'rating': str(obj.driver.rating),
                'latitude': str(obj.driver.current_latitude or ''),
                'longitude': str(obj.driver.current_longitude or ''),
            }
        return None

    def get_preparer_info(self, obj):
        if obj.preparer:
            return {
                'id': str(obj.preparer.id),
                'name': obj.preparer.full_name,
                'phone': obj.preparer.phone,
            }
        return None

    def get_customer_info(self, obj):
        # Agents need this; customers viewing their own order get redundant info.
        return {
            'id': str(obj.customer.id),
            'name': obj.customer.full_name,
            'phone': obj.customer.phone,
        }


class OrderListSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source='customer.full_name', read_only=True)
    driver_name = serializers.CharField(source='driver.full_name', read_only=True, allow_null=True)
    preparer_name = serializers.CharField(source='preparer.full_name', read_only=True, allow_null=True)
    items_count = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = ['id', 'order_number', 'order_id', 'store', 'status', 'total_amount',
                  'payment_method', 'payment_status',
                  'customer_name', 'driver_name', 'preparer_name', 'items_count',
                  'created_at', 'accepted_at', 'preparing_at', 'out_for_delivery_at',
                  'delivered_at', 'cancelled_at']

    def get_items_count(self, obj):
        return obj.items.count()


class OrderItemCreateSerializer(serializers.Serializer):
    product_id = serializers.UUIDField()
    qty = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0.001, required=False)
    quantity = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0.001, required=False)

    def validate(self, attrs):
        if not attrs.get('qty') and not attrs.get('quantity'):
            raise serializers.ValidationError('qty (or quantity) is required')
        attrs['qty'] = attrs.get('qty') or attrs.get('quantity')
        return attrs


class OrderCreateSerializer(serializers.Serializer):
    """Spec-shape: { address_id, items[{product_id, qty}], payment_method, notes, promo_code, points_to_use }."""
    address_id = serializers.IntegerField()
    items = OrderItemCreateSerializer(many=True)
    payment_method = serializers.ChoiceField(
        choices=[c[0] for c in Order.PaymentMethod.choices],
        default=Order.PaymentMethod.CASH,
    )
    notes = serializers.CharField(required=False, allow_blank=True, default='')
    customer_notes = serializers.CharField(required=False, allow_blank=True, default='')
    promo_code = serializers.CharField(required=False, allow_blank=True, default='')
    points_to_use = serializers.IntegerField(min_value=0, default=0)
    store_id = serializers.IntegerField(required=False)
    branch_id = serializers.IntegerField(required=False)


class AdjustPriceSerializer(serializers.Serializer):
    new_price = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0)
    reason = serializers.CharField(required=False, allow_blank=True, default='')


class AdjustQuantitySerializer(serializers.Serializer):
    actual_qty = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0, required=False)
    new_quantity = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0, required=False)
    reason = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        if attrs.get('actual_qty') is None and attrs.get('new_quantity') is None:
            raise serializers.ValidationError('actual_qty (or new_quantity) is required')
        attrs['actual_qty'] = attrs.get('actual_qty') if attrs.get('actual_qty') is not None else attrs.get('new_quantity')
        return attrs


class AdjustWeightSerializer(serializers.Serializer):
    weight_actual = serializers.DecimalField(max_digits=10, decimal_places=3, min_value=0)
    reason = serializers.CharField(required=False, allow_blank=True, default='')


class SubstituteItemSerializer(serializers.Serializer):
    substitute_product_id = serializers.UUIDField()
    reason = serializers.CharField(required=False, allow_blank=True, default='')


class AddItemSerializer(serializers.Serializer):
    product_id = serializers.UUIDField()
    qty = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0.001, required=False)
    quantity = serializers.DecimalField(max_digits=8, decimal_places=3, min_value=0.001, required=False)
    reason = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        if not attrs.get('qty') and not attrs.get('quantity'):
            raise serializers.ValidationError('qty (or quantity) is required')
        attrs['qty'] = attrs.get('qty') or attrs.get('quantity')
        return attrs


class DriverDeliveredSerializer(serializers.Serializer):
    amount_collected = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0, required=False)
    delivery_photo_url = serializers.URLField(required=False, allow_blank=True)
    proof_image = serializers.ImageField(required=False)
    notes = serializers.CharField(required=False, allow_blank=True, default='')


class CancelOrderSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default='')


class ApproveAdjustmentSerializer(serializers.Serializer):
    adjustment_id = serializers.IntegerField()
    approved = serializers.BooleanField()


class AssignSerializer(serializers.Serializer):
    preparer_id = serializers.UUIDField(required=False)
    driver_id = serializers.UUIDField(required=False)

    def validate(self, attrs):
        if not attrs.get('preparer_id') and not attrs.get('driver_id'):
            raise serializers.ValidationError('preparer_id or driver_id required')
        return attrs


class ActionLogSerializer(serializers.Serializer):
    action_type = serializers.ChoiceField(
        choices=[c[0] for c in OrderAdjustment.AdjustmentType.choices]
    )
    data = serializers.JSONField(required=False, default=dict)
    reason = serializers.CharField(required=False, allow_blank=True, default='')
