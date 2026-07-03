from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from django.db.models import Q, F
from django.utils import timezone
from django.core.cache import cache

from .models import Product, Category, Banner, MediaLibrary, StockWaitlist, ProductImage
from .serializers import (
    ProductSerializer, ProductListSerializer, CategorySerializer,
    BannerSerializer, MediaLibrarySerializer, ProductCreateSerializer,
    ProductImageSerializer,
)
from apps.users.permissions import IsAdminUser
from apps.core.permissions import IsAdminWriteOrSupportRead
from apps.core.scoping import scope_to_user, enforce_store_id_on_create
from apps.core.responses import ok, fail
from apps.core.cache_keys import categories_key, banners_key, CATEGORIES_CACHE_TTL, BANNERS_CACHE_TTL


# ─── Customer-facing ─────────────────────────────────────────────────────────

def _filter_store(queryset, request):
    """Apply ?store_id= filter for customer-facing endpoints."""
    store_id = request.query_params.get('store_id')
    if store_id:
        try:
            queryset = queryset.filter(store_id=int(store_id))
        except (ValueError, TypeError):
            pass
    return queryset


def _expire_discounts(queryset):
    """Auto-expire discounts whose discount_end has passed."""
    now = timezone.now()
    Product.objects.filter(
        discount_end__lt=now, discount_price__isnull=False
    ).update(discount_price=None, discount_percentage=None, discount_start=None, discount_end=None)
    return queryset


class ProductListView(generics.ListAPIView):
    serializer_class = ProductListSerializer
    permission_classes = [permissions.AllowAny]
    search_fields = ['name_ar', 'name_en', 'barcode', 'description_ar', 'description_en']
    ordering_fields = ['original_price', 'name_en', 'created_at']

    def get_queryset(self):
        qs = Product.objects.filter(is_available=True, is_active=True).select_related('store').prefetch_related(
            'categories', 'images'
        )
        qs = _expire_discounts(qs)
        qs = _filter_store(qs, self.request)

        category_id = self.request.query_params.get('category_id') or self.request.query_params.get('category')
        if category_id:
            qs = qs.filter(categories__id=category_id)

        branch_id = self.request.query_params.get('branch_id') or self.request.query_params.get('branch')
        if branch_id:
            qs = qs.filter(
                Q(branch_id=branch_id) | Q(branch_stock__branch_id=branch_id, branch_stock__is_available=True)
            ).distinct()

        is_available_q = self.request.query_params.get('is_available')
        if is_available_q is not None:
            qs = qs.filter(is_available=is_available_q in ('1', 'true', 'True'))

        has_discount = self.request.query_params.get('has_discount')
        if has_discount in ('1', 'true', 'True'):
            qs = qs.filter(discount_price__isnull=False)

        search = self.request.query_params.get('search')
        if search:
            qs = qs.filter(
                Q(name_ar__icontains=search) | Q(name_en__icontains=search) |
                Q(barcode__icontains=search)
            )

        featured = self.request.query_params.get('featured')
        if featured:
            qs = qs.filter(is_featured=True)

        return qs


class ProductDetailView(generics.RetrieveAPIView):
    serializer_class = ProductSerializer
    permission_classes = [permissions.AllowAny]
    queryset = Product.objects.all().prefetch_related('categories', 'images', 'branch_stock')
    lookup_field = 'id'


class ProductByBarcodeView(APIView):
    """Public barcode lookup — used by both customer (rare) and agent app."""
    permission_classes = [permissions.AllowAny]

    def get(self, request, barcode):
        store_id = request.query_params.get('store_id')
        qs = Product.objects.filter(barcode=barcode)
        if store_id:
            qs = qs.filter(store_id=store_id)
        product = qs.first()
        if not product:
            return fail('Product not found', status_code=status.HTTP_404_NOT_FOUND)
        return ok(ProductSerializer(product, context={'request': request}).data)


class SearchSuggestionsView(APIView):
    """Autocomplete typeahead."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        q = (request.query_params.get('q') or request.query_params.get('search') or '').strip()
        if len(q) < 1:
            return ok([])
        qs = Product.objects.filter(is_available=True, is_active=True)
        qs = _filter_store(qs, request)
        qs = qs.filter(
            Q(name_ar__istartswith=q) | Q(name_en__istartswith=q) |
            Q(barcode__startswith=q) | Q(name_ar__icontains=q) | Q(name_en__icontains=q)
        )[:10]
        return ok(ProductListSerializer(qs, many=True, context={'request': request}).data)


class ProductSearchView(generics.ListAPIView):
    """Full search with pagination."""
    serializer_class = ProductListSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        q = (self.request.query_params.get('q') or self.request.query_params.get('search') or '').strip()
        qs = Product.objects.filter(is_available=True, is_active=True)
        qs = _filter_store(qs, self.request)
        if q:
            qs = qs.filter(
                Q(name_ar__icontains=q) | Q(name_en__icontains=q) |
                Q(barcode__icontains=q) | Q(description_ar__icontains=q)
            )
        return qs.prefetch_related('categories', 'images')


class CategoryListView(generics.ListAPIView):
    serializer_class = CategorySerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = None  # categories list is short — return all

    def get_queryset(self):
        store_id = self.request.query_params.get('store_id')
        # Cache key
        cache_k = categories_key(store_id) if store_id else None
        if cache_k:
            cached_ids = cache.get(cache_k)
        else:
            cached_ids = None
        qs = Category.objects.filter(is_visible=True, is_active=True)
        if store_id:
            try:
                qs = qs.filter(store_id=int(store_id))
            except (ValueError, TypeError):
                pass
        return qs.order_by('sort_order', 'name_en')


class CategoryProductsView(generics.ListAPIView):
    serializer_class = ProductListSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        cat_id = self.kwargs['pk']
        return (
            Product.objects.filter(is_available=True, is_active=True, categories__id=cat_id)
            .prefetch_related('categories', 'images')
        )


class WaitlistAddView(APIView):
    """POST /products/waitlist — body: { product_id }"""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        product_id = request.data.get('product_id')
        if not product_id:
            return fail('product_id required', status_code=400)
        try:
            product = Product.objects.get(id=product_id)
        except Product.DoesNotExist:
            return fail('Product not found', status_code=404)
        entry, created = StockWaitlist.objects.get_or_create(
            product=product, user=request.user,
        )
        return ok({'subscribed': True, 'created': created})


class WaitlistRemoveView(APIView):
    """DELETE /products/waitlist/:productId"""
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, product_id):
        deleted, _ = StockWaitlist.objects.filter(
            product_id=product_id, user=request.user
        ).delete()
        if not deleted:
            return fail('Not subscribed', status_code=404)
        return ok({'subscribed': False})


class WaitlistToggleView(APIView):
    """Legacy toggle endpoint."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, product_id):
        try:
            product = Product.objects.get(id=product_id)
        except Product.DoesNotExist:
            return fail('Product not found', status_code=404)
        entry, created = StockWaitlist.objects.get_or_create(
            product=product, user=request.user
        )
        if not created:
            entry.delete()
            return ok({'subscribed': False})
        return ok({'subscribed': True})


class BannerListView(generics.ListAPIView):
    serializer_class = BannerSerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        qs = Banner.objects.filter(is_active=True)
        store_id = self.request.query_params.get('store_id')
        if store_id:
            qs = qs.filter(store_id=store_id)

        # Active window
        qs = qs.filter(
            Q(publish_at__isnull=True) | Q(publish_at__lte=now),
        ).filter(
            Q(expire_at__isnull=True) | Q(expire_at__gte=now),
        ).filter(
            Q(start_date__isnull=True) | Q(start_date__lte=now),
        ).filter(
            Q(end_date__isnull=True) | Q(end_date__gte=now),
        )

        position = self.request.query_params.get('position')
        if position:
            qs = qs.filter(position=position)
        return qs.order_by('sort_order')


class BannerClickView(APIView):
    """Track banner clicks. Atomic increment (fixed from buggy Q(...) version)."""
    permission_classes = [permissions.AllowAny]

    def post(self, request, pk):
        Banner.objects.filter(pk=pk).update(click_count=F('click_count') + 1)
        return ok({'tracked': True})


# ─── Admin ────────────────────────────────────────────────────────────────────

class AdminProductListView(generics.ListAPIView):
    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    search_fields = ['name_ar', 'name_en', 'barcode']
    filterset_fields = ['is_available', 'is_featured', 'branch', 'sell_unit', 'store']

    def get_queryset(self):
        qs = Product.objects.all().select_related('store').prefetch_related('categories', 'images')
        return scope_to_user(qs, self.request.user)


class AdminProductCreateView(generics.CreateAPIView):
    serializer_class = ProductCreateSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)


class AdminProductDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ProductCreateSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    parser_classes = [MultiPartParser, FormParser, JSONParser]
    lookup_field = 'id'

    def get_queryset(self):
        return scope_to_user(Product.objects.all(), self.request.user)

    def destroy(self, request, *args, **kwargs):
        """Soft delete — keep history."""
        product = self.get_object()
        product.is_available = False
        product.save(update_fields=['is_available'])
        return ok({'id': str(product.id), 'is_available': False}, message='Soft-deleted')


class AdminProductImagesView(APIView):
    """GET list / POST upload gallery images for a product."""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def _product(self, request, product_id):
        return scope_to_user(Product.objects.all(), request.user).filter(id=product_id).first()

    def get(self, request, product_id):
        from .image_gallery import serialize_gallery
        product = self._product(request, product_id)
        if not product:
            return fail('Product not found', status_code=404)
        return ok(serialize_gallery(product, request))

    def post(self, request, product_id):
        from .image_gallery import add_gallery_images, serialize_gallery
        product = self._product(request, product_id)
        if not product:
            return fail('Product not found', status_code=404)
        created, err = add_gallery_images(product, request)
        if err:
            return fail(err, status_code=400)
        return ok(serialize_gallery(product, request),
                  message=f'{len(created)} image(s) added')


class AdminProductImageDetailView(APIView):
    """PATCH (reorder / set primary / alt) or DELETE a gallery image."""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def _image(self, request, product_id, pk):
        product = scope_to_user(Product.objects.all(), request.user).filter(id=product_id).first()
        if not product:
            return None
        return product.images.filter(pk=pk).first()

    def patch(self, request, product_id, pk):
        from .image_gallery import update_gallery_image
        image = self._image(request, product_id, pk)
        if not image:
            return fail('Image not found', status_code=404)
        update_gallery_image(image, request.data)
        return ok(ProductImageSerializer(image, context={'request': request}).data)

    def delete(self, request, product_id, pk):
        image = self._image(request, product_id, pk)
        if not image:
            return fail('Image not found', status_code=404)
        image.delete()
        return ok({'id': pk}, message='Image deleted')


class AdminToggleAvailabilityView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request, product_id):
        try:
            qs = scope_to_user(Product.objects.all(), request.user)
            product = qs.get(id=product_id)
        except Product.DoesNotExist:
            return fail('Product not found', status_code=404)
        product.is_available = not product.is_available
        product.save(update_fields=['is_available'])

        # WS invalidation hint to admin dashboard
        try:
            from channels.layers import get_channel_layer
            from asgiref.sync import async_to_sync
            cl = get_channel_layer()
            if cl:
                async_to_sync(cl.group_send)('admin_dashboard', {
                    'type': 'product_availability_changed',
                    'product_id': str(product.id),
                    'is_available': product.is_available,
                })
        except Exception:
            pass

        if product.is_available:
            try:
                from apps.orders.tasks import notify_stock_waitlist
                notify_stock_waitlist.delay(str(product.id))
            except Exception:
                pass

        return ok({'is_available': product.is_available, 'product_id': str(product.id)})


class AdminProductBulkView(APIView):
    """
    POST /admin/products/bulk
    Body: { action: 'set_available'|'set_unavailable'|'set_featured'|'price_update'|'delete',
            product_ids: [...], payload: {...} }
    """
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    ALLOWED_ACTIONS = {'set_available', 'set_unavailable', 'set_featured', 'price_update', 'delete'}

    def post(self, request):
        action = request.data.get('action')
        product_ids = request.data.get('product_ids') or []
        payload = request.data.get('payload') or {}

        if action not in self.ALLOWED_ACTIONS:
            return fail(f'action must be one of {sorted(self.ALLOWED_ACTIONS)}', status_code=400)
        if not isinstance(product_ids, list) or not product_ids:
            return fail('product_ids must be a non-empty list', status_code=400)

        qs = scope_to_user(Product.objects.filter(id__in=product_ids), request.user)
        updated = 0
        if action == 'set_available':
            updated = qs.update(is_available=True)
        elif action == 'set_unavailable':
            updated = qs.update(is_available=False)
        elif action == 'set_featured':
            updated = qs.update(is_featured=bool(payload.get('value', True)))
        elif action == 'price_update':
            # multiplier or fixed adjustment
            multiplier = payload.get('multiplier')
            delta = payload.get('delta')
            for p in qs:
                if multiplier is not None:
                    p.original_price = round(float(p.original_price) * float(multiplier), 2)
                elif delta is not None:
                    p.original_price = max(0, float(p.original_price) + float(delta))
                p.save(update_fields=['original_price'])
                updated += 1
        elif action == 'delete':
            updated = qs.update(is_available=False)  # soft delete
        return ok({'updated': updated, 'action': action})


class AdminProductWaitlistView(generics.ListAPIView):
    """GET /admin/products/:id/waitlist"""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get(self, request, product_id):
        entries = (
            StockWaitlist.objects.filter(product_id=product_id, notified_at__isnull=True)
            .select_related('user')
        )
        data = [{
            'id': e.id,
            'user_id': str(e.user.id),
            'user_name': e.user.full_name,
            'user_phone': e.user.phone,
            'created_at': e.created_at,
        } for e in entries]
        return ok(data)


class AdminProductNotifyWaitlistView(APIView):
    """POST /admin/products/:id/notify-waitlist"""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def post(self, request, product_id):
        from apps.orders.tasks import notify_stock_waitlist
        notify_stock_waitlist.delay(str(product_id))
        return ok({'queued': True})


# Category admin
class AdminCategoryListView(generics.ListCreateAPIView):
    serializer_class = CategorySerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    pagination_class = None  # short list — return ALL categories (was capped at 20)

    def get_queryset(self):
        return scope_to_user(Category.objects.all(), self.request.user).order_by('sort_order', 'id')

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)
        cache.delete(categories_key(getattr(self.request.user, 'store_id', None) or 'all'))


class AdminCategoryDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = CategorySerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def get_queryset(self):
        return scope_to_user(Category.objects.all(), self.request.user)

    def destroy(self, request, *args, **kwargs):
        cat = self.get_object()
        if cat.products.exists():
            return fail('Cannot delete a category with products. Move or delete products first.',
                        status_code=400)
        cache.delete(categories_key(cat.store_id))
        return super().destroy(request, *args, **kwargs)

    def perform_update(self, serializer):
        obj = serializer.save()
        cache.delete(categories_key(obj.store_id))


class AdminCategoryReorderView(APIView):
    """PATCH /admin/categories/reorder — body: [{id, sort_order}, ...]"""
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]

    def patch(self, request):
        items = request.data if isinstance(request.data, list) else request.data.get('items', [])
        if not isinstance(items, list):
            return fail('Body must be a list', status_code=400)
        qs = scope_to_user(Category.objects.all(), request.user)
        updated = 0
        for it in items:
            try:
                qs.filter(pk=int(it['id'])).update(sort_order=int(it['sort_order']))
                updated += 1
            except (KeyError, TypeError, ValueError):
                continue
        return ok({'updated': updated})


# Banner admin
class AdminBannerListView(generics.ListCreateAPIView):
    serializer_class = BannerSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get_queryset(self):
        return scope_to_user(Banner.objects.all(), self.request.user)

    def perform_create(self, serializer):
        enforce_store_id_on_create(serializer, self.request.user)
        cache.delete(banners_key(getattr(self.request.user, 'store_id', None) or 'all'))


class AdminBannerDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = BannerSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminWriteOrSupportRead]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get_queryset(self):
        return scope_to_user(Banner.objects.all(), self.request.user)

    def perform_update(self, serializer):
        obj = serializer.save()
        cache.delete(banners_key(obj.store_id))


# Media Library
class MediaLibraryListView(generics.ListCreateAPIView):
    serializer_class = MediaLibrarySerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    queryset = MediaLibrary.objects.all()
    parser_classes = [MultiPartParser, FormParser]

    def perform_create(self, serializer):
        serializer.save(uploaded_by=self.request.user)


class MediaLibraryDetailView(generics.RetrieveDestroyAPIView):
    serializer_class = MediaLibrarySerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    queryset = MediaLibrary.objects.all()


# Import (Excel/CSV, upsert by barcode) — synchronous with dry-run support
class AdminProductImportView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    parser_classes = [MultiPartParser]

    def post(self, request):
        from . import importer
        from .models import ProductImportJob

        upload = request.FILES.get('file')
        if not upload:
            return fail('file is required (multipart field "file")', status_code=400)
        name = upload.name.lower()
        if not (name.endswith('.xlsx') or name.endswith('.csv')):
            return fail('Only .xlsx and .csv files are supported', status_code=400)

        dry_run = str(request.data.get('dry_run', '')).lower() in ('1', 'true')
        store_id = request.data.get('store_id')
        try:
            store_id = int(store_id) if store_id else None
        except (ValueError, TypeError):
            store_id = None

        try:
            rows = importer.parse_file(upload, upload.name)
        except Exception as e:
            return fail(f'Could not read file: {e}', status_code=400)
        if not rows:
            return fail('File contains no data rows', status_code=400)

        result = importer.run_import(rows, request.user, store_id, dry_run=dry_run)
        result['dry_run'] = dry_run

        if not dry_run:
            ProductImportJob.objects.create(
                store_id=getattr(request.user, 'store_id', None) or store_id,
                user=request.user,
                filename=upload.name,
                total_rows=result['total_rows'],
                created_count=result['created'],
                updated_count=result['updated'],
                error_count=len(result['errors']),
                errors=result['errors'][:500],
                warnings=result['warnings'][:500],
            )
        return ok(result)


class AdminProductImportTemplateView(APIView):
    """GET template .xlsx; ?include=products fills it with existing products."""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        from django.http import HttpResponse
        from . import importer

        products = None
        filename = 'product_import_template.xlsx'
        if request.query_params.get('include') == 'products':
            products = scope_to_user(Product.objects.all(), request.user).prefetch_related('categories')
            filename = 'products_export.xlsx'
        wb = importer.build_template_workbook(products)
        resp = HttpResponse(
            content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        resp['Content-Disposition'] = f'attachment; filename="{filename}"'
        wb.save(resp)
        return resp


class AdminProductImportHistoryView(APIView):
    """GET list of past imports (most recent first)."""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        from .models import ProductImportJob
        qs = scope_to_user(ProductImportJob.objects.select_related('user'), request.user)[:50]
        return ok([{
            'id': j.id,
            'filename': j.filename,
            'user': getattr(j.user, 'full_name', None) or getattr(j.user, 'phone', None) or '',
            'total_rows': j.total_rows,
            'created': j.created_count,
            'updated': j.updated_count,
            'error_count': j.error_count,
            'errors': j.errors,
            'warnings': j.warnings,
            'created_at': j.created_at.isoformat(),
        } for j in qs])
