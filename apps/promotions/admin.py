from django.contrib import admin
from .models import Promotion, DeliveryFee, PromotionUsage


@admin.register(Promotion)
class PromotionAdmin(admin.ModelAdmin):
    list_display = ('id', 'name_en', 'code', 'store', 'discount_type', 'discount_value',
                    'used_count', 'usage_limit', 'is_active', 'start_at', 'end_at')
    list_filter = ('store', 'is_active', 'discount_type')
    search_fields = ('name_ar', 'name_en', 'code')


@admin.register(DeliveryFee)
class DeliveryFeeAdmin(admin.ModelAdmin):
    list_display = ('id', 'zone_name', 'branch', 'store', 'fee', 'is_active')
    list_filter = ('store', 'is_active')
    search_fields = ('zone_name',)


@admin.register(PromotionUsage)
class PromotionUsageAdmin(admin.ModelAdmin):
    list_display = ('id', 'promotion', 'user', 'order', 'discount_applied', 'created_at')
    list_filter = ('promotion',)
