"""A generated WebP thumbnail per product, for list screens.

Product is tracked by simple-history, so the column has to land on
HistoricalProduct too — otherwise every write to a product fails on the
history insert.
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0006_banner_optional_image_and_title_en'),
    ]

    operations = [
        migrations.AddField(
            model_name='product',
            name='thumbnail',
            field=models.ImageField(blank=True, null=True, upload_to='products/thumbs/'),
        ),
        migrations.AddField(
            model_name='historicalproduct',
            name='thumbnail',
            # History rows store the path only — no file handling on a snapshot.
            field=models.TextField(blank=True, max_length=100, null=True),
        ),
    ]
