"""
Shared helpers for managing a product's image gallery (ProductImage rows).

Used by both the admin endpoints (apps/products/views.py) and the agent
inventory endpoints (apps/orders/agent_views.py) so the upload/optimize/delete
logic lives in one place. The product's `main_image` remains the primary
image; these are additional gallery photos shown in a carousel.
"""
from django.db.models import Max

from .models import ProductImage
from .serializers import ProductImageSerializer
from apps.core.validators import validate_image_upload, optimize_image_file


def serialize_gallery(product, request):
    return ProductImageSerializer(
        product.images.all(), many=True, context={'request': request}
    ).data


def _collect_files(request):
    files = []
    if hasattr(request.FILES, 'getlist'):
        files = request.FILES.getlist('images') or request.FILES.getlist('image')
    if not files and 'image' in request.FILES:
        files = [request.FILES['image']]
    return files


def add_gallery_images(product, request):
    """Create ProductImage rows from uploaded files. Returns (created, error)."""
    files = _collect_files(request)
    if not files:
        return None, 'No image file provided (send "images" or "image")'

    base_order = product.images.aggregate(m=Max('sort_order'))['m'] or 0
    created = []
    for i, f in enumerate(files, start=1):
        validate_image_upload(f)
        optimized = optimize_image_file(f)
        img = ProductImage.objects.create(
            product=product,
            image=optimized,
            sort_order=base_order + i,
            is_primary=False,
        )
        created.append(img)
    return created, None


def update_gallery_image(image, data):
    """PATCH a single gallery image: sort_order, is_primary, alt text."""
    fields = []
    if 'sort_order' in data:
        try:
            image.sort_order = int(data['sort_order'])
            fields.append('sort_order')
        except (TypeError, ValueError):
            pass
    for f in ('alt_text_ar', 'alt_text_en'):
        if f in data:
            setattr(image, f, data[f] or '')
            fields.append(f)
    if 'is_primary' in data:
        val = data['is_primary']
        is_primary = val if isinstance(val, bool) else str(val).lower() in ('true', '1', 'yes')
        image.is_primary = is_primary
        fields.append('is_primary')
        if is_primary:
            # Only one primary per product.
            ProductImage.objects.filter(product=image.product).exclude(
                pk=image.pk).update(is_primary=False)
    if fields:
        image.save(update_fields=fields)
    return image
