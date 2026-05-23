from rest_framework import generics, permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from django.core.cache import cache

from .models import Store
from .serializers import (
    StoreCardSerializer, StoreDetailSerializer,
    StoreAdminSerializer, MultistoreSettingsSerializer,
)
from apps.core.responses import ok, fail
from apps.core.cache_keys import APP_SETTINGS_CACHE_KEY, STORES_LIST_CACHE_KEY
from apps.notifications.models import AppSettings


# ─── Public / customer ────────────────────────────────────────────────────────

class StoreConfigView(APIView):
    """
    Called by the Flutter customer app on launch. Tells the client whether to
    show the store-selector grid (multistore_enabled=1) or load a single store
    directly (multistore_enabled=0 → default_store_id).
    """
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        cached = cache.get(APP_SETTINGS_CACHE_KEY)
        if cached:
            enabled = cached.get('multistore_enabled', '0') == '1'
            default_id = cached.get('default_store_id')
            default_id = int(default_id) if default_id and default_id.isdigit() else None
        else:
            enabled = AppSettings.get('multistore_enabled', '0') == '1'
            default_id_raw = AppSettings.get('default_store_id', '')
            default_id = int(default_id_raw) if default_id_raw.isdigit() else None

        return ok({
            'multistore_enabled': enabled,
            'default_store_id': default_id,
        })


class StoreListView(generics.ListAPIView):
    """
    Customer-app store grid. Only available when multistore_enabled=1.
    """
    serializer_class = StoreCardSerializer
    permission_classes = [permissions.AllowAny]

    def list(self, request, *args, **kwargs):
        if AppSettings.get('multistore_enabled', '0') != '1':
            return fail(
                'Single-store mode is enabled. Use /api/v1/stores/config to fetch default_store_id.',
                status_code=status.HTTP_404_NOT_FOUND,
            )
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        return Store.objects.filter(is_active=True).order_by('sort_order', 'name_en')


class StoreDetailView(generics.RetrieveAPIView):
    serializer_class = StoreDetailSerializer
    permission_classes = [permissions.AllowAny]
    queryset = Store.objects.filter(is_active=True)


# ─── Admin (Super Admin only) ─────────────────────────────────────────────────

class IsSuperAdminOnly(permissions.BasePermission):
    """Super Admin = role=admin AND store_id IS NULL."""
    def has_permission(self, request, view):
        u = request.user
        return (
            u.is_authenticated
            and u.role == 'admin'
            and getattr(u, 'store_id', None) is None
        )


class AdminStoreListCreateView(generics.ListCreateAPIView):
    serializer_class = StoreAdminSerializer
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminOnly]
    queryset = Store.objects.all().order_by('sort_order', 'name_en')

    def perform_create(self, serializer):
        store = serializer.save()
        cache.delete(STORES_LIST_CACHE_KEY)
        return store


class AdminStoreDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = StoreAdminSerializer
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminOnly]
    queryset = Store.objects.all()

    def perform_update(self, serializer):
        serializer.save()
        cache.delete(STORES_LIST_CACHE_KEY)


class AdminStoreToggleStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminOnly]

    def patch(self, request, pk):
        try:
            store = Store.objects.get(pk=pk)
        except Store.DoesNotExist:
            return fail('Store not found', status_code=status.HTTP_404_NOT_FOUND)
        store.is_active = not store.is_active
        store.save(update_fields=['is_active', 'updated_at'])
        cache.delete(STORES_LIST_CACHE_KEY)
        return ok({'id': store.id, 'is_active': store.is_active})


class AdminStoreReorderView(APIView):
    """
    Body: [{ "id": 1, "sort_order": 0 }, { "id": 2, "sort_order": 1 }, ...]
    """
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminOnly]

    def patch(self, request):
        items = request.data if isinstance(request.data, list) else request.data.get('items', [])
        if not isinstance(items, list):
            return fail('Body must be a list of {id, sort_order}', status_code=400)
        updated = 0
        for it in items:
            try:
                Store.objects.filter(pk=it['id']).update(sort_order=int(it['sort_order']))
                updated += 1
            except (KeyError, ValueError, TypeError):
                continue
        cache.delete(STORES_LIST_CACHE_KEY)
        return ok({'updated': updated})


class AdminMultistoreSettingsView(APIView):
    """
    GET — current value. PATCH — toggle multistore_enabled and/or set
    default_store_id. Super Admin only. Invalidates app-settings cache.
    """
    permission_classes = [permissions.IsAuthenticated, IsSuperAdminOnly]

    def get(self, request):
        enabled = AppSettings.get('multistore_enabled', '0') == '1'
        default_id_raw = AppSettings.get('default_store_id', '')
        default_id = int(default_id_raw) if default_id_raw.isdigit() else None
        return ok({
            'multistore_enabled': enabled,
            'default_store_id': default_id,
        })

    def patch(self, request):
        ser = MultistoreSettingsSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        data = ser.validated_data

        if 'multistore_enabled' in data:
            AppSettings.objects.update_or_create(
                key='multistore_enabled',
                defaults={
                    'value': '1' if data['multistore_enabled'] else '0',
                    'description': 'Show store selector in customer app (1) or single-store mode (0)',
                },
            )
        if 'default_store_id' in data and data['default_store_id'] is not None:
            if not Store.objects.filter(pk=data['default_store_id']).exists():
                return fail('default_store_id does not exist', status_code=400)
            AppSettings.objects.update_or_create(
                key='default_store_id',
                defaults={
                    'value': str(data['default_store_id']),
                    'description': 'Store to load when multistore_enabled=0',
                },
            )

        cache.delete(APP_SETTINGS_CACHE_KEY)
        cache.delete(STORES_LIST_CACHE_KEY)

        return ok({
            'multistore_enabled': AppSettings.get('multistore_enabled', '0') == '1',
            'default_store_id': AppSettings.get('default_store_id', None),
        })
