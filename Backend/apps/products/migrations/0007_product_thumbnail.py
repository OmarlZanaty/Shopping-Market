"""A generated WebP thumbnail per product, for list screens."""
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
    ]
