"""Banner artwork may be a URL, and the English title is optional.

Both fields were mandatory at the DB level, so a banner created from the
dashboard (Arabic title, media-library URL, no uploaded file) could never be
saved — which is why the table was empty in production.
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0005_deactivate_tobacco_category'),
    ]

    operations = [
        migrations.AlterField(
            model_name='banner',
            name='image',
            field=models.ImageField(blank=True, null=True, upload_to='banners/'),
        ),
        migrations.AlterField(
            model_name='banner',
            name='title_en',
            field=models.CharField(blank=True, max_length=200),
        ),
    ]
