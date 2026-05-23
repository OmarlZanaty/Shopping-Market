from django.urls import path
from . import views

urlpatterns = [
    # Customer / public
    path('config/', views.StoreConfigView.as_view(), name='stores-config'),
    path('', views.StoreListView.as_view(), name='stores-list'),
    path('<int:pk>/', views.StoreDetailView.as_view(), name='stores-detail'),

    # Super-Admin only
    path('admin/all/', views.AdminStoreListCreateView.as_view(), name='admin-stores'),
    path('admin/<int:pk>/', views.AdminStoreDetailView.as_view(), name='admin-store-detail'),
    path('admin/<int:pk>/status/', views.AdminStoreToggleStatusView.as_view(), name='admin-store-status'),
    path('admin/reorder/', views.AdminStoreReorderView.as_view(), name='admin-store-reorder'),
    path('admin/settings/multistore/', views.AdminMultistoreSettingsView.as_view(), name='admin-multistore-settings'),
]
