from django.db import migrations, models

PG_FORWARD = """
    ALTER TABLE products_product
        ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

    ALTER TABLE products_historicalproduct
        ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
"""

PG_REVERSE = """
    ALTER TABLE products_product
        DROP COLUMN IF EXISTS is_active;

    ALTER TABLE products_historicalproduct
        DROP COLUMN IF EXISTS is_active;
"""

TABLES = ('products_product', 'products_historicalproduct')


def _columns(schema_editor, table):
    connection = schema_editor.connection
    with connection.cursor() as cursor:
        return {
            col.name
            for col in connection.introspection.get_table_description(cursor, table)
        }


def add_is_active(apps, schema_editor):
    """Postgres keeps its original IF NOT EXISTS DDL verbatim. Other backends
    (SQLite, which the test settings use) have no IF NOT EXISTS on ADD COLUMN,
    so the same idempotency is achieved by introspecting first."""
    if schema_editor.connection.vendor == 'postgresql':
        schema_editor.execute(PG_FORWARD)
        return
    for table in TABLES:
        if 'is_active' not in _columns(schema_editor, table):
            schema_editor.execute(
                f'ALTER TABLE {schema_editor.quote_name(table)} '
                'ADD COLUMN is_active BOOL NOT NULL DEFAULT 1'
            )


def drop_is_active(apps, schema_editor):
    if schema_editor.connection.vendor == 'postgresql':
        schema_editor.execute(PG_REVERSE)
        return
    for table in TABLES:
        if 'is_active' in _columns(schema_editor, table):
            schema_editor.execute(
                f'ALTER TABLE {schema_editor.quote_name(table)} DROP COLUMN is_active'
            )


class Migration(migrations.Migration):
    """
    Adds is_active to both the main Product table and the
    django-simple-history mirror table.

    Idempotent        →  safe to run even if the columns already exist.
    state_operations  →  keeps Django's migration state model in sync so
                         makemigrations never flags spurious changes.
    """

    dependencies = [
        ('products', '0002_initial'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(add_is_active, drop_is_active),
            ],
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
