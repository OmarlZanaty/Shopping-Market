from django.db import migrations


class Migration(migrations.Migration):
    """
    Adds is_active to both the main Product table and the
    django-simple-history mirror table.

    Uses IF NOT EXISTS so this migration is safe to run even if the
    columns were already added manually (e.g. via ALTER TABLE) and
    will never crash on repeated docker restarts.
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
        ),
    ]
