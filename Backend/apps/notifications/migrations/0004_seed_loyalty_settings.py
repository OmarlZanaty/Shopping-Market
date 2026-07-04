from django.db import migrations
from decimal import Decimal


# Smart loyalty defaults. Fully editable afterwards from the dashboard
# (Loyalty settings page). The engine lives in apps.orders.loyalty.
#
# Defaults below mirror the legacy flat rates (1 pt/EGP earn, 0.05 EGP/pt
# redeem) so behaviour is unchanged until an admin tunes them:
DEFAULTS = [
    ('loyalty_enabled', '1', 'تفعيل نظام نقاط الولاء'),
    ('loyalty_earn_points', '1', 'عدد النقاط الممنوحة لكل شريحة إنفاق'),
    ('loyalty_earn_per_egp', '1', 'قيمة شريحة الإنفاق بالجنيه (نقاط لكل X جنيه)'),
    ('loyalty_redeem_points', '20', 'عدد النقاط المطلوبة مقابل خصم'),
    ('loyalty_redeem_egp', '1', 'قيمة الخصم بالجنيه مقابل عدد النقاط المحدد'),
    ('loyalty_min_redeem', '0', 'أقل عدد نقاط يمكن استبداله في الطلب الواحد'),
    ('loyalty_max_redeem_percent', '100', 'أقصى نسبة خصم من قيمة الطلب عبر النقاط (%)'),
]


def seed(apps, schema_editor):
    AppSettings = apps.get_model('notifications', 'AppSettings')

    def existing(key):
        row = AppSettings.objects.filter(key=key).first()
        return row.value if row else None

    # Derive earn/redeem blocks from any legacy flat rates so tuned installs
    # keep their economics.
    legacy_earn = existing('loyalty_earn_rate')          # points per EGP
    legacy_redeem = existing('loyalty_redeem_rate')      # EGP per point

    overrides = {}
    if legacy_earn:
        try:
            overrides['loyalty_earn_points'] = str(int(Decimal(legacy_earn)))
            overrides['loyalty_earn_per_egp'] = '1'
        except Exception:
            pass
    if legacy_redeem:
        try:
            # redeem_egp per redeem_points where redeem_points=100 for precision
            overrides['loyalty_redeem_points'] = '100'
            overrides['loyalty_redeem_egp'] = str(Decimal(legacy_redeem) * 100)
        except Exception:
            pass

    for key, value, description in DEFAULTS:
        AppSettings.objects.get_or_create(
            key=key,
            defaults={'value': overrides.get(key, value), 'description': description},
        )


def unseed(apps, schema_editor):
    AppSettings = apps.get_model('notifications', 'AppSettings')
    AppSettings.objects.filter(key__in=[k for k, _, _ in DEFAULTS]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('notifications', '0003_seed_delivery_settings'),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
