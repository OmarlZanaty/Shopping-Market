"""
Downscale + recompress existing product images in place.

Product photos were uploaded as full-size originals (often 1–2 MB), which makes
list grids slow to load. This re-encodes each Product.main_image to a max of
800px on the long edge, keeping the same storage path/filename so DB references
stay valid. Idempotent: already-small images are left untouched.

    python manage.py optimize_product_images            # process all
    python manage.py optimize_product_images --dry-run  # report only
    python manage.py optimize_product_images --max-dim 600
"""
from io import BytesIO

from django.core.management.base import BaseCommand
from django.core.files.storage import default_storage

from apps.products.models import Product


class Command(BaseCommand):
    help = 'Resize/recompress existing product main_image files in place.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true')
        parser.add_argument('--max-dim', type=int, default=800)

    def handle(self, *args, **opts):
        from PIL import Image

        dry = opts['dry_run']
        max_dim = opts['max_dim']

        qs = Product.objects.exclude(main_image='').only('id', 'main_image')
        total = qs.count()
        self.stdout.write(f'Scanning {total} products with an uploaded image…')

        processed = skipped = failed = 0
        saved_before = saved_after = 0

        for p in qs.iterator():
            name = p.main_image.name
            try:
                if not default_storage.exists(name):
                    skipped += 1
                    continue
                before = default_storage.size(name)
                with default_storage.open(name, 'rb') as fh:
                    img = Image.open(fh)
                    img.load()

                ext = name.rsplit('.', 1)[-1].lower() if '.' in name else 'jpg'
                is_png = ext == 'png'
                is_webp = ext == 'webp'

                if max(img.size) <= max_dim and before < 250 * 1024:
                    skipped += 1
                    continue

                if not is_png and not is_webp:
                    if img.mode in ('RGBA', 'LA', 'P'):
                        img = img.convert('RGBA')
                        bg = Image.new('RGBA', img.size, (255, 255, 255, 255))
                        img = Image.alpha_composite(bg, img).convert('RGB')
                    else:
                        img = img.convert('RGB')
                elif img.mode == 'P':
                    img = img.convert('RGBA')

                if max(img.size) > max_dim:
                    img.thumbnail((max_dim, max_dim), Image.LANCZOS)

                buf = BytesIO()
                if is_png:
                    img.save(buf, format='PNG', optimize=True)
                elif is_webp:
                    img.save(buf, format='WEBP', quality=82, method=4)
                else:
                    img.save(buf, format='JPEG', quality=82, optimize=True, progressive=True)
                data = buf.getvalue()

                if len(data) >= before:
                    # Recompression didn't help — keep the original.
                    skipped += 1
                    continue

                saved_before += before
                saved_after += len(data)
                processed += 1

                if dry:
                    self.stdout.write(f'  would shrink {name}: {before//1024}KB → {len(data)//1024}KB')
                    continue

                default_storage.delete(name)
                from django.core.files.base import ContentFile
                default_storage.save(name, ContentFile(data))
            except Exception as e:  # noqa: BLE001
                failed += 1
                self.stderr.write(f'  FAILED {name}: {e}')

        mb = lambda b: b / (1024 * 1024)
        self.stdout.write(self.style.SUCCESS(
            f'Done. processed={processed} skipped={skipped} failed={failed} '
            f'| saved {mb(saved_before):.1f}MB → {mb(saved_after):.1f}MB '
            f'({mb(saved_before - saved_after):.1f}MB freed){" [dry-run]" if dry else ""}'
        ))
