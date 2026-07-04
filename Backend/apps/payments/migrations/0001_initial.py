# Generated for apps.payments — initial schema for Paymob transactions.

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('orders', '0002_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='PaymobTransaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('transaction_type', models.CharField(choices=[('order_payment', 'Order Payment'), ('adjustment_top_up', 'Price Adjustment Top-Up')], default='order_payment', max_length=30)),
                ('status', models.CharField(choices=[('pending', 'Pending'), ('paid', 'Paid'), ('failed', 'Failed'), ('voided', 'Voided'), ('refunded', 'Refunded')], default='pending', max_length=20)),
                ('amount_egp', models.DecimalField(decimal_places=2, max_digits=10)),
                ('amount_cents', models.PositiveBigIntegerField()),
                ('paymob_order_id', models.CharField(blank=True, max_length=200)),
                ('paymob_payment_key', models.CharField(blank=True, max_length=500)),
                ('paymob_transaction_id', models.CharField(blank=True, help_text='Filled in by the Paymob webhook on payment success.', max_length=200)),
                ('webhook_data', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('adjustment', models.ForeignKey(blank=True, help_text='Set when this payment is for an adjustment top-up.', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='paymob_transactions', to='orders.orderadjustment')),
                ('customer', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='paymob_transactions', to=settings.AUTH_USER_MODEL)),
                ('order', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='paymob_transactions', to='orders.order')),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='paymobtransaction',
            index=models.Index(fields=['order', '-created_at'], name='pay_tx_order_created_idx'),
        ),
        migrations.AddIndex(
            model_name='paymobtransaction',
            index=models.Index(fields=['status'], name='pay_tx_status_idx'),
        ),
        migrations.AddIndex(
            model_name='paymobtransaction',
            index=models.Index(fields=['paymob_transaction_id'], name='pay_tx_paymobtx_idx'),
        ),
    ]
