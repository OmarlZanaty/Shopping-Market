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


def safe_filename(name):
    """Strip risky chars from an uploaded filename."""
    if not name:
        return 'file'
    base = name.rsplit('/', 1)[-1].rsplit('\\', 1)[-1]
    return UNSAFE_FILENAME_CHARS.sub('_', base)[:200]
