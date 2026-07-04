from django.contrib import admin
from .models import PaymobTransaction


@admin.register(PaymobTransaction)
class PaymobTransactionAdmin(admin.ModelAdmin):
    list_display = ('id', 'order', 'transaction_type', 'amount_egp', 'status', 'created_at')
    list_filter = ('status', 'transaction_type')
    search_fields = ('order__order_number', 'paymob_order_id', 'paymob_transaction_id')
    readonly_fields = ('paymob_order_id', 'paymob_payment_key', 'paymob_transaction_id',
                       'webhook_data', 'created_at', 'updated_at')
    ordering = ('-created_at',)
