# -*- coding: utf-8 -*-
"""
Product thumbnails.

The catalogue is 450x800 PNGs averaging 56 KB. A product grid shows twenty of
them at roughly 150 px wide, so the phone was downloading — and decoding at full
resolution — about twenty times the pixels it draws. That is the "app is slow to
open and images take forever" the customers reported.

A thumbnail is a WebP no wider than THUMB_WIDTH. WebP because it is a third the
size of the equivalent PNG and every Android and iOS version the app supports
decodes it natively.

Generation is best-effort by design: a product whose file is missing or corrupt
must still save. It simply keeps serving its full image.
"""
import logging
import os

from django.core.files.base import ContentFile

logger = logging.getLogger('apps')

# Wide enough for a 2-column grid on a 3x-density phone without being the full
# image again.
THUMB_WIDTH = 300
THUMB_QUALITY = 80


def _thumb_name(source_name):
    # Filename only: the field's upload_to already puts it under
    # products/thumbs/, and returning a path here nested it twice.
    stem, _ = os.path.splitext(os.path.basename(source_name))
    return f'{stem}.webp'


def build_thumbnail(image_field):
    """(name, ContentFile) for this image, or None if one cannot be made."""
    try:
        from PIL import Image
    except ImportError:  # pragma: no cover — Pillow is in requirements
        logger.warning('Pillow missing — thumbnails disabled')
        return None

    try:
        image_field.open()
        with Image.open(image_field) as img:
            img.load()
            # WebP keeps alpha, so a cut-out product photo stays cut out; only
            # exotic modes (P, CMYK) need converting.
            if img.mode not in ('RGB', 'RGBA'):
                img = img.convert('RGBA' if 'A' in img.getbands() else 'RGB')
            if img.width > THUMB_WIDTH:
                height = max(1, round(img.height * THUMB_WIDTH / img.width))
                img = img.resize((THUMB_WIDTH, height), Image.LANCZOS)

            from io import BytesIO
            buf = BytesIO()
            img.save(buf, format='WEBP', quality=THUMB_QUALITY, method=4)
            buf.seek(0)
            return _thumb_name(image_field.name), ContentFile(buf.read())
    except Exception as e:  # noqa: BLE001 — a bad file must not block the save
        logger.warning('thumbnail failed for %s: %s', getattr(image_field, 'name', '?'), e)
        return None
    finally:
        try:
            image_field.close()
        except Exception:
            pass


def ensure_thumbnail(product, force=False):
    """Give this product a thumbnail if it has an uploaded image and none yet.

    Returns True when one was written.
    """
    if not product.main_image:
        return False
    if product.thumbnail and not force:
        return False

    built = build_thumbnail(product.main_image)
    if not built:
        return False
    name, content = built
    # save=False then one explicit save: two DB writes per product across a
    # 1,459-row backfill is worth avoiding.
    product.thumbnail.save(name, content, save=False)
    product.save(update_fields=['thumbnail'])
    return True
