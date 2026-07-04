from django.contrib import admin
from .models import ProductRecommendation, TrendingProduct


@admin.register(ProductRecommendation)
class ProductRecommendationAdmin(admin.ModelAdmin):
    list_display = ('user', 'product', 'score', 'source', 'computed_at')
    list_filter = ('source',)
    search_fields = ('user__phone', 'product__name_en', 'product__name_ar')
    ordering = ('-score',)
    readonly_fields = ('computed_at',)


@admin.register(TrendingProduct)
class TrendingProductAdmin(admin.ModelAdmin):
    list_display = ('product', 'store', 'order_count_7d', 'score', 'computed_at')
    list_filter = ('store',)
    search_fields = ('product__name_en', 'product__name_ar')
    ordering = ('-score',)
    readonly_fields = ('computed_at',)
