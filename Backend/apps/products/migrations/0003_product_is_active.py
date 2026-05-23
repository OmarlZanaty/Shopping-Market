from django.db import migrations, models


class Migration(migrations.Migration):
    """
    Adds is_active to both the main Product table and the
    django-simple-history mirror table.

    RunSQL with IF NOT EXISTS  →  safe to run even if columns already exist.
    state_operations           →  keeps Django's migration state model in sync
                                  so makemigrations never flags spurious changes.
    """

    dependencies = [
        ('products', '0002_initial'),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
                ALTER TABLE products_product
                    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

                ALTER TABLE products_historicalproduct
                    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
            """,
            reverse_sql="""
                ALTER TABLE products_product
                    DROP COLUMN IF EXISTS is_active;

                ALTER TABLE products_historicalproduct
                    DROP COLUMN IF EXISTS is_active;
            """,
            state_operations=[
                migrations.AddField(
                    model_name='product',
                    name='is_active',
                    field=models.BooleanField(default=True),
                ),
                migrations.AddField(
                    model_name='historicalproduct',
                    name='is_active',
                    field=models.BooleanField(default=True),
                ),
            ],
        ),
    ]
