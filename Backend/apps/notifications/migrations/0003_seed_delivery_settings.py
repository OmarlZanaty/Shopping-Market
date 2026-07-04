from django.db import migrations


# Default delivery-zone settings. Editable afterwards from the admin dashboard
# (Settings page). The client app reads these from GET /notifications/settings/.
DEFAULTS = [
    ('delivery_radius_km', '4',
     'أقصى مسافة للتوصيل بالكيلومتر — الطلبات الأبعد من ذلك تُرفض'),
    ('store_latitude', '29.227922', 'خط عرض موقع المتجر'),
    ('store_longitude', '32.622006', 'خط طول موقع المتجر'),
]


def seed(apps, schema_editor):
    AppSettings = apps.get_model('notifications', 'AppSettings')
    for key, value, description in DEFAULTS:
        # Only create if missing — never clobber an admin-edited value.
        AppSettings.objects.get_or_create(
            key=key, defaults={'value': value, 'description': description})


def unseed(apps, schema_editor):
    AppSettings = apps.get_model('notifications', 'AppSettings')
    AppSettings.objects.filter(
        key__in=[k for k, _, _ in DEFAULTS]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('notifications', '0002_initial'),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
