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

        categories_data = data['categories']   # [{sort_order, name_ar}, …]
        products_data   = data['products']     # [{barcode, name_ar, category, price}, …]

        # ── Resolve default store ─────────────────────────────────────────────
        store = Store.objects.filter(name_en='Shopping Market').first()
        if not store:
            store = Store.objects.first()
        if not store:
            self.stderr.write(self.style.ERROR(
                'No store found. Run `python manage.py seed_default_store` first.'
            ))
            return
        self.stdout.write(f'Using store: {store.name_en} (id={store.id})')

        with transaction.atomic():
            # ── Optional clear ────────────────────────────────────────────────
            if options['clear']:
                deleted_p, _ = Product.objects.filter(store=store).delete()
                deleted_c, _ = Category.objects.filter(store=store).delete()
                self.stdout.write(
                    self.style.WARNING(f'Cleared {deleted_c} categories, {deleted_p} products')
                )

            # ── Seed categories ───────────────────────────────────────────────
            cat_map = {}   # name_ar → Category instance
            cat_created = 0
            for c in categories_data:
                name_ar = c['name_ar']
                obj, created = Category.objects.get_or_create(
                    store=store,
                    name_ar=name_ar,
                    defaults={
                        'name_en': name_ar,   # use Arabic as fallback English name
                        'sort_order': c['sort_order'],
                        'is_active': True,
                        'is_visible': True,
                    },
                )
                cat_map[name_ar] = obj
                if created:
                    cat_created += 1

            self.stdout.write(
                self.style.SUCCESS(f'✓ Categories: {cat_created} created, {len(categories_data) - cat_created} already existed')
            )

            # ── Seed products ─────────────────────────────────────────────────
            prod_created = 0
            prod_updated = 0
            prod_skipped = 0
            unknown_cats  = set()

            BATCH = 500
            to_create = []
            to_update_ids = []

            for p in products_data:
                barcode  = p['barcode']
                name_ar  = p['name_ar']
                cat_name = p['category']
                price    = p['price'] or 0.0

                category = cat_map.get(cat_name)
                if category is None:
                    # Category referenced in products but not in category sheet —
                    # create it on the fly.
                    unknown_cats.add(cat_name)
                    category, _ = Category.objects.get_or_create(
                        store=store,
                        name_ar=cat_name,
                        defaults={'name_en': cat_name, 'is_active': True, 'is_visible': True},
                    )
                    cat_map[cat_name] = category

                existing = Product.objects.filter(barcode=barcode).first()
                if existing:
                    # Update price if it has a real value and product has 0
                    if price > 0 and existing.original_price == 0:
                        existing.original_price = price
                        existing.save(update_fields=['original_price'])
                        prod_updated += 1
                    else:
                        prod_skipped += 1
                    continue

                # Determine if weight-based (fresh produce, deli items have price=0)
                is_weight = price == 0

                to_create.append(Product(
                    store=store,
                    barcode=barcode,
                    name_ar=name_ar,
                    name_en=name_ar,          # English name = Arabic until translated
                    original_price=price,
                    is_available=True,
                    is_weight_based=is_weight,
                    quantity_in_stock=999 if not is_weight else 0,
                ))
                # Attach category after bulk_create (M2M needs PKs)
                # We'll save the mapping as (barcode, cat_name) and wire after bulk
                if len(to_create) >= BATCH:
                    created_objs = Product.objects.bulk_create(to_create, ignore_conflicts=True)
                    prod_created += len(created_objs)
                    to_create = []

                    # Wire M2M for this batch
                    self._wire_categories(cat_map, products_data, prod_created - len(created_objs))

            # Final batch
            if to_create:
                created_objs = Product.objects.bulk_create(to_create, ignore_conflicts=True)
                prod_created += len(created_objs)
                to_create = []

            # Wire all categories via M2M (single pass over all products by barcode)
            self.stdout.write('Wiring product→category relationships …')
            self._wire_all_categories(store, cat_map, products_data)

        if unknown_cats:
            self.stdout.write(
                self.style.WARNING(f'  Auto-created {len(unknown_cats)} extra categories: {unknown_cats}')
            )
        self.stdout.write(self.style.SUCCESS(
            f'✓ Products: {prod_created} created, {prod_updated} price-updated, {prod_skipped} skipped (already up-to-date)'
        ))

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _wire_all_categories(self, store, cat_map, products_data):
        """Set the M2M category for every product in one efficient pass."""
        from apps.products.models import Product

        # Build barcode → category lookup
        barcode_to_cat = {}
        for p in products_data:
            cat = cat_map.get(p['category'])
            if cat:
                barcode_to_cat[p['barcode']] = cat

        # Fetch all store products as a dict
        qs = Product.objects.filter(store=store).only('id', 'barcode')
        products_by_barcode = {prod.barcode: prod for prod in qs}

        # Use through model bulk approach to avoid N+1
        ThroughModel = Product.categories.through  # ProductCategory join table
        existing_links = set(
            ThroughModel.objects.filter(
                product__store=store
            ).values_list('product_id', 'category_id')
        )

        to_add = []
        for barcode, cat in barcode_to_cat.items():
            prod = products_by_barcode.get(barcode)
            if prod and (prod.id, cat.id) not in existing_links:
                to_add.append(ThroughModel(product_id=prod.id, category_id=cat.id))

        if to_add:
            ThroughModel.objects.bulk_create(to_add, ignore_conflicts=True)
            self.stdout.write(f'  Linked {len(to_add)} product-category pairs')
