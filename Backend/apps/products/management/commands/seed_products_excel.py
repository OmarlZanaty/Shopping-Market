"""
Imports all categories and products from the bundled JSON seed file
(generated from الاقسام والاصناف .xlsx).

Usage:
    python manage.py seed_products_excel
    python manage.py seed_products_excel --clear   # wipe existing first
"""
import json
import os
from django.core.management.base import BaseCommand
from django.db import transaction


class Command(BaseCommand):
    help = 'Seed 36 categories + 10 440 products from the Excel seed data'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear', action='store_true',
            help='Delete existing categories & products for this store before seeding',
        )

    def handle(self, *args, **options):
        from apps.stores.models import Store
        from apps.products.models import Category, Product

        # ── Load JSON data file ───────────────────────────────────────────────
        data_file = os.path.join(os.path.dirname(__file__), 'products_seed_data.json')
        self.stdout.write(f'Loading data from {data_file} …')
        with open(data_file, encoding='utf-8') as f:
            data = json.load(f)

        categories_data = data['categories']
        products_data   = data['products']

        # ── Resolve default store ─────────────────────────────────────────────
        store = Store.objects.filter(name_en='Shopping Market').first() or Store.objects.first()
        if not store:
            self.stderr.write(self.style.ERROR(
                'No store found. Run `python manage.py seed_default_store` first.'
            ))
            return
        self.stdout.write(f'Using store: {store.name_en} (id={store.id})')

        with transaction.atomic():

            # ── Optional clear ────────────────────────────────────────────────
            if options['clear']:
                dp, _ = Product.objects.filter(store=store).delete()
                dc, _ = Category.objects.filter(store=store).delete()
                self.stdout.write(self.style.WARNING(f'Cleared {dc} categories, {dp} products'))

            # ── Seed categories ───────────────────────────────────────────────
            cat_map = {}
            cat_created = 0
            for c in categories_data:
                name_ar = c['name_ar']
                obj, created = Category.objects.get_or_create(
                    store=store,
                    name_ar=name_ar,
                    defaults={
                        'name_en': name_ar,
                        'sort_order': c['sort_order'],
                        'is_active': True,
                        'is_visible': True,
                    },
                )
                cat_map[name_ar] = obj
                if created:
                    cat_created += 1

            self.stdout.write(self.style.SUCCESS(
                f'✓ Categories: {cat_created} created, {len(categories_data) - cat_created} already existed'
            ))

            # ── Seed products (bulk_create in batches of 500) ─────────────────
            BATCH = 500
            batch = []
            prod_created = 0
            prod_skipped = 0

            # Pre-fetch existing barcodes to skip duplicates
            existing_barcodes = set(
                Product.objects.filter(store=store).values_list('barcode', flat=True)
            )

            for p in products_data:
                barcode  = p['barcode']
                name_ar  = p['name_ar']
                cat_name = p['category']
                price    = float(p['price']) if p['price'] else 0.0

                if barcode in existing_barcodes:
                    prod_skipped += 1
                    continue

                # Auto-create any category that appears in products but not in sheet
                if cat_name not in cat_map:
                    obj, _ = Category.objects.get_or_create(
                        store=store, name_ar=cat_name,
                        defaults={'name_en': cat_name, 'is_active': True, 'is_visible': True},
                    )
                    cat_map[cat_name] = obj

                batch.append(Product(
                    store=store,
                    barcode=barcode,
                    name_ar=name_ar,
                    name_en=name_ar,
                    original_price=price,
                    is_available=True,
                    is_weight_based=(price == 0),
                    quantity_in_stock=0 if price == 0 else 999,
                ))
                existing_barcodes.add(barcode)

                if len(batch) >= BATCH:
                    Product.objects.bulk_create(batch, ignore_conflicts=True)
                    prod_created += len(batch)
                    batch = []
                    self.stdout.write(f'  … {prod_created} products inserted so far')

            if batch:
                Product.objects.bulk_create(batch, ignore_conflicts=True)
                prod_created += len(batch)

            self.stdout.write(self.style.SUCCESS(
                f'✓ Products: {prod_created} created, {prod_skipped} skipped (already exist)'
            ))

            # ── Wire M2M product → category ───────────────────────────────────
            self.stdout.write('Wiring product→category relationships …')

            barcode_to_cat = {p['barcode']: cat_map.get(p['category']) for p in products_data}

            all_products = {
                prod.barcode: prod
                for prod in Product.objects.filter(store=store).only('id', 'barcode')
            }

            ThroughModel = Product.categories.through
            existing_links = set(
                ThroughModel.objects.filter(
                    product__store=store
                ).values_list('product_id', 'category_id')
            )

            links = []
            for barcode, cat in barcode_to_cat.items():
                prod = all_products.get(barcode)
                if prod and cat and (prod.id, cat.id) not in existing_links:
                    links.append(ThroughModel(product_id=prod.id, category_id=cat.id))

            if links:
                ThroughModel.objects.bulk_create(links, ignore_conflicts=True)

            self.stdout.write(self.style.SUCCESS(
                f'✓ Linked {len(links)} product-category pairs'
            ))

        self.stdout.write(self.style.SUCCESS('\n🎉 Done! All products imported successfully.'))
