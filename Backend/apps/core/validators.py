"""
Validators used across serializers.
"""
import re

from django.core.exceptions import ValidationError
from rest_framework import serializers


EGYPTIAN_PHONE_RE = re.compile(r'^01[0125]\d{8}$')  # 11 digits, starts with 010/011/012/015
HEX_COLOR_RE = re.compile(r'^#[0-9A-Fa-f]{6}$')


def validate_egyptian_phone(value):
    if not value:
        raise serializers.ValidationError('Phone is required')
    cleaned = ''.join(c for c in str(value) if c.isdigit())
    if not EGYPTIAN_PHONE_RE.match(cleaned):
        raise serializers.ValidationError(
            'Phone must be an 11-digit Egyptian number starting with 010/011/012/015'
        )
    return cleaned


def validate_hex_color(value):
    if not value:
        return value
    if not HEX_COLOR_RE.match(value):
        raise serializers.ValidationError('Color must be a 7-character hex string like #FF6B35')
    return value


# File upload safety

ALLOWED_IMAGE_MIME = {'image/jpeg', 'image/png', 'image/webp'}
MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB

UNSAFE_FILENAME_CHARS = re.compile(r'[^a-zA-Z0-9._-]')


def validate_image_upload(file_obj):
    """Reject files that fail MIME, size, or filename-safety checks."""
    if file_obj is None:
        return
    if hasattr(file_obj, 'size') and file_obj.size > MAX_IMAGE_BYTES:
        raise serializers.ValidationError(f'Image must be ≤ {MAX_IMAGE_BYTES // (1024*1024)} MB')
    content_type = getattr(file_obj, 'content_type', None)
    if content_type and content_type not in ALLOWED_IMAGE_MIME:
        raise serializers.ValidationError(
            f'Image type must be one of {sorted(ALLOWED_IMAGE_MIME)}; got {content_type}'
        )
    name = getattr(file_obj, 'name', '') or ''
    if '..' in name or '/' in name or '\\' in name:
        raise serializers.ValidationError('Invalid filename')
    return file_obj


def optimize_image_file(file_obj, *, max_dim=800):
    """
    Downscale an uploaded image to ``max_dim`` on its longest edge and
    recompress it, keeping the original format/extension. Product photos are
    frequently 1–2 MB originals; serving those in list grids is slow. Returns a
    Django ContentFile (same name) ready to assign to an ImageField, or the
    original ``file_obj`` if processing isn't possible.
    """
    try:
        from io import BytesIO
        from PIL import Image
        from django.core.files.base import ContentFile

        name = getattr(file_obj, 'name', '') or 'image'
        ext = name.rsplit('.', 1)[-1].lower() if '.' in name else 'jpg'

        try:
            file_obj.seek(0)
        except Exception:
            pass
        img = Image.open(file_obj)

        is_png = ext == 'png'
        is_webp = ext == 'webp'
        if not is_png and not is_webp:
            ext = 'jpg'

        # Flatten transparency onto white for JPEG (which has no alpha).
        if ext == 'jpg' and img.mode in ('RGBA', 'LA', 'P'):
            img = img.convert('RGBA')
            bg = Image.new('RGBA', img.size, (255, 255, 255, 255))
            img = Image.alpha_composite(bg, img).convert('RGB')
        elif img.mode == 'P':
            img = img.convert('RGBA')

        # Only downscale; never upscale.
        if max(img.size) > max_dim:
            img.thumbnail((max_dim, max_dim), Image.LANCZOS)

        buf = BytesIO()
        if is_png:
            img.save(buf, format='PNG', optimize=True)
        elif is_webp:
            img.save(buf, format='WEBP', quality=82, method=4)
        else:
            img.save(buf, format='JPEG', quality=82, optimize=True, progressive=True)
        buf.seek(0)
        return ContentFile(buf.read(), name=name)
    except Exception:
        # Any decode/encode failure — fall back to the original upload.
        try:
            file_obj.seek(0)
        except Exception:
            pass
        return file_obj


def safe_filename(name):
    """Strip risky chars from an uploaded filename."""
    if not name:
        return 'file'
    base = name.rsplit('/', 1)[-1].rsplit('\\', 1)[-1]
    return UNSAFE_FILENAME_CHARS.sub('_', base)[:200]
