"""
Generate the ~300px WebP thumbnail for every product that has an uploaded image
and no thumbnail yet.

New uploads get one automatically; this is for the catalogue that already
existed when thumbnails were added. Safe to re-run — products that already have
one are skipped unless --force is given.

    python manage.py backfill_thumbnails
    python manage.py backfill_thumbnails --dry-run
    python manage.py backfill_thumbnails --force        # regenerate all
"""
from django.core.management.base import BaseCommand

from apps.products.models import Product
from apps.products.thumbnails import ensure_thumbnail


class Command(BaseCommand):
    help = 'Generate WebP thumbnails for existing product images.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true')
        parser.add_argument('--force', action='store_true',
                            help='Regenerate even when a thumbnail exists')
        parser.add_argument('--limit', type=int, default=0)

    def handle(self, *args, **opts):
        qs = Product.objects.exclude(main_image='').exclude(main_image__isnull=True)
        if not opts['force']:
            qs = qs.filter(thumbnail__in=['', None])
        if opts['limit']:
            qs = qs[:opts['limit']]

        total = qs.count() if not opts['limit'] else len(qs)
        self.stdout.write(f'{total} product(s) to process')
        if opts['dry_run']:
            return

        done = skipped = 0
        # .iterator() so a full-catalogue run does not hold every row in memory.
        for product in qs.iterator(chunk_size=200):
            if ensure_thumbnail(product, force=opts['force']):
                done += 1
            else:
                skipped += 1
            if (done + skipped) % 200 == 0:
                self.stdout.write(f'  ...{done + skipped}/{total}')

        self.stdout.write(self.style.SUCCESS(
            f'thumbnails written: {done}, skipped/failed: {skipped}'))
