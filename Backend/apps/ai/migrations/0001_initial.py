# Generated for apps.ai — initial schema for recommendation engine.

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('products', '0003_product_is_active'),
        ('stores', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='ProductRecommendation',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('score', models.FloatField(default=0.0, help_text='Higher = more relevant')),
                ('source', models.CharField(choices=[('collab', 'Collaborative Filtering'), ('frequency', 'Purchase Frequency'), ('trending', 'Trending in Store')], max_length=20)),
                ('computed_at', models.DateTimeField(auto_now=True)),
                ('product', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='recommendations', to='products.product')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='product_recommendations', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-score'],
            },
        ),
        migrations.CreateModel(
            name='TrendingProduct',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('order_count_7d', models.PositiveIntegerField(default=0)),
                ('score', models.FloatField(default=0.0)),
                ('computed_at', models.DateTimeField(auto_now=True)),
                ('product', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trending_entries', to='products.product')),
                ('store', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trending_products', to='stores.store')),
            ],
            options={
                'ordering': ['-score'],
            },
        ),
        migrations.AddIndex(
            model_name='productrecommendation',
            index=models.Index(fields=['user', '-score'], name='ai_prodrec_user_score_idx'),
        ),
        migrations.AddIndex(
            model_name='productrecommendation',
            index=models.Index(fields=['computed_at'], name='ai_prodrec_computed_idx'),
        ),
        migrations.AlterUniqueTogether(
            name='productrecommendation',
            unique_together={('user', 'product')},
        ),
        migrations.AddIndex(
            model_name='trendingproduct',
            index=models.Index(fields=['store', '-score'], name='ai_trend_store_score_idx'),
        ),
        migrations.AlterUniqueTogether(
            name='trendingproduct',
            unique_together={('product', 'store')},
        ),
    ]
