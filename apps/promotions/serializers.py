from rest_framework import serializers
from .models import Promotion, DeliveryFee


class PromotionSerializer(serializers.ModelSerializer):
    is_currently_valid = serializers.ReadOnlyField()

    class Meta:
        model = Promotion
        fields = '__all__'
        read_only_fields = ['used_count', 'created_at', 'updated_at']


class DeliveryFeeSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryFee
        fields = '__all__'
