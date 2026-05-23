from django.contrib import admin
from .models import Store


@admin.register(Store)
class StoreAdmin(admin.ModelAdmin):
    list_display = ('id', 'name_en', 'name_ar', 'type', 'is_active', 'sort_order', 'min_order_amount')
    list_filter = ('type', 'is_active')
    search_fields = ('name_ar', 'name_en')
    ordering = ('sort_order',)
