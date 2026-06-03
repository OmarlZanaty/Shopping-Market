"""
Management command: hide all products from the customer app.

Usage (on the server):
    docker compose exec web python manage.py hide_all_products
    docker compose exec web python manage.py hide_all_products --show   # reverse: make all visible again
"""

from django.core.management.base import BaseCommand
from apps.products.models import Product


class Command(BaseCommand):
    help = 'Hide all products from the customer app (set is_available=False)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--show',
            action='store_true',
            help='Reverse: make all products visible again (set is_available=True)',
        )
        parser.add_argument(
            '--store',
            type=int,
            default=None,
            help='Only affect products in this store ID (default: all stores)',
        )

    def handle(self, *args, **options):
        qs = Product.objects.all()

        store_id = options.get('store')
        if store_id:
            qs = qs.filter(store_id=store_id)
            self.stdout.write(f'Scoped to store {store_id}')

        if options['show']:
            count = qs.update(is_available=True)
            self.stdout.write(self.style.SUCCESS(
                f'✅ Made {count} products VISIBLE (is_available=True)'
            ))
        else:
            count = qs.update(is_available=False)
            self.stdout.write(self.style.SUCCESS(
                f'✅ Hidden {count} products from customers (is_available=False)'
            ))
