from django.db import migrations

# Apple App Review (guideline 1.4.3 - Safety - Physical Harm) rejected the app
# because this category sells shisha molasses / vape products, which App
# Review considers "content that encourages the use of tobacco, nicotine, or
# vaping products". Google Play's tobacco policy prohibits the same, so this
# is deactivated store-wide rather than just hidden on iOS.
TOBACCO_CATEGORY_NAME_AR = "السجائر و مستلزماتها"


def deactivate_tobacco_category(apps, schema_editor):
    Category = apps.get_model('products', 'Category')
    categories = Category.objects.filter(name_ar=TOBACCO_CATEGORY_NAME_AR)
    categories.update(is_active=False, is_visible=False)
    for category in categories:
        category.products.update(is_active=False)


def reverse_noop(apps, schema_editor):
    # Deliberately a no-op — re-enabling tobacco sales should be a manual,
    # reviewed decision, not an automatic migration rollback.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0004_productimportjob'),
    ]

    operations = [
        migrations.RunPython(deactivate_tobacco_category, reverse_noop),
    ]
