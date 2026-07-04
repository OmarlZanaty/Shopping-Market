from django.contrib import admin
from django.urls import path, include, re_path
from django.conf import settings
from django.views.static import serve as _media_serve
from django.views.generic import TemplateView
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView

urlpatterns = [
    # Django Admin
    path('django-admin/', admin.site.urls),

    # OpenAPI docs
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),

    # ───────── v1 (spec uses /api/...; we mount under /api/v1/ for forward-compat) ─────────
    path('api/v1/auth/', include('apps.users.urls')),
    path('api/v1/stores/', include('apps.stores.urls')),
    path('api/v1/products/', include('apps.products.urls')),
    path('api/v1/categories/', include(('apps.products.category_urls', 'categories'), namespace='categories')),
    path('api/v1/orders/', include('apps.orders.urls')),
    path('api/v1/agent/', include(('apps.orders.agent_urls', 'agent'), namespace='agent')),
    path('api/v1/admin/', include(('apps.orders.admin_urls', 'admin_orders'), namespace='admin_orders')),
    path('api/v1/branches/', include('apps.branches.urls')),
    path('api/v1/promotions/', include('apps.promotions.urls')),
    path('api/v1/notifications/', include('apps.notifications.urls')),
    path('api/v1/wallet/', include(('apps.users.wallet_urls', 'wallet'), namespace='wallet')),
    path('api/v1/ratings/', include(('apps.orders.rating_urls', 'ratings'), namespace='ratings')),
    path('api/v1/reports/', include(('apps.analytics.reports.urls', 'reports'), namespace='reports')),
    path('api/v1/analytics/', include('apps.analytics.urls')),
    path('api/v1/', include(('apps.core.urls', 'core'), namespace='core')),
    path('privacy-policy/', TemplateView.as_view(template_name='privacy_policy.html'), name='privacy_policy'),

    # ───────── Spec-shape aliases (no v1 prefix, matches the prompt verbatim) ─────────
    path('api/auth/', include('apps.users.urls')),
    path('api/stores/', include(('apps.stores.urls', 'stores2'), namespace='stores_alias')),
]

# Serve uploaded media in ALL environments. The mobile apps hit gunicorn (:8000)
# directly, bypassing nginx, so Django itself must serve /media/ — the usual
# static() helper only does this when DEBUG=True (here DEBUG=False in prod),
# which left uploaded product images returning 404 (blank image after save).
if not getattr(settings, 'USE_S3', False):
    urlpatterns += [
        re_path(r'^media/(?P<path>.*)$', _media_serve,
                {'document_root': settings.MEDIA_ROOT}),
    ]
