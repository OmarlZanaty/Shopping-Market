from django.urls import path
from . import views

urlpatterns = [
    # Customer / public
    path('', views.ProductListView.as_view(), name='product-list'),
    path('search/', views.ProductSearchView.as_view(), name='product-search'),
    path('search/suggestions/', views.SearchSuggestionsView.as_view(), name='search-suggestions'),
    path('barcode/<str:barcode>/', views.ProductByBarcodeView.as_view(), name='product-by-barcode'),
    path('categories/', views.CategoryListView.as_view(), name='categories'),
    path('banners/', views.BannerListView.as_view(), name='banners'),
    path('banners/<int:pk>/click/', views.BannerClickView.as_view(), name='banner-click'),

    # Waitlist
    path('waitlist/', views.WaitlistAddView.as_view(), name='waitlist-add'),
    path('waitlist/<uuid:product_id>/', views.WaitlistRemoveView.as_view(), name='waitlist-remove'),
    path('<uuid:product_id>/waitlist/', views.WaitlistToggleView.as_view(), name='waitlist-toggle'),  # legacy

    # Detail LAST so /search and /barcode/ etc. don't collide
    path('<uuid:id>/', views.ProductDetailView.as_view(), name='product-detail'),

    # Admin
    path('admin/products/', views.AdminProductListView.as_view(), name='admin-products'),
    path('admin/products/create/', views.AdminProductCreateView.as_view(), name='admin-product-create'),
    path('admin/products/bulk/', views.AdminProductBulkView.as_view(), name='admin-product-bulk'),
    path('admin/products/import/', views.AdminProductImportView.as_view(), name='admin-product-import'),
    path('admin/products/<uuid:id>/', views.AdminProductDetailView.as_view(), name='admin-product-detail'),
    path('admin/products/<uuid:product_id>/images/', views.AdminProductImagesView.as_view(),
         name='admin-product-images'),
    path('admin/products/<uuid:product_id>/images/<int:pk>/', views.AdminProductImageDetailView.as_view(),
         name='admin-product-image-detail'),
    path('admin/products/<uuid:product_id>/availability/', views.AdminToggleAvailabilityView.as_view(),
         name='admin-product-availability'),
    path('admin/products/<uuid:product_id>/waitlist/', views.AdminProductWaitlistView.as_view(),
         name='admin-product-waitlist'),
    path('admin/products/<uuid:product_id>/notify-waitlist/', views.AdminProductNotifyWaitlistView.as_view(),
         name='admin-product-notify-waitlist'),

    path('admin/categories/', views.AdminCategoryListView.as_view(), name='admin-categories'),
    path('admin/categories/reorder/', views.AdminCategoryReorderView.as_view(), name='admin-categories-reorder'),
    path('admin/categories/<int:pk>/', views.AdminCategoryDetailView.as_view(), name='admin-category-detail'),

    path('admin/banners/', views.AdminBannerListView.as_view(), name='admin-banners'),
    path('admin/banners/<int:pk>/', views.AdminBannerDetailView.as_view(), name='admin-banner-detail'),

    path('admin/media/', views.MediaLibraryListView.as_view(), name='admin-media'),
    path('admin/media/<int:pk>/', views.MediaLibraryDetailView.as_view(), name='admin-media-detail'),
]
