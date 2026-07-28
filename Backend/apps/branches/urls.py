from django.urls import path
from . import views

urlpatterns = [
    path('', views.BranchListView.as_view(), name='branches'),
    path('admin/', views.AdminBranchView.as_view(), name='admin-branches'),
    path('admin/<int:pk>/', views.AdminBranchDetailView.as_view(), name='admin-branch-detail'),
    path('admin/<int:pk>/status/', views.AdminBranchStatusToggleView.as_view(), name='admin-branch-status'),

    # Delivery zones. `coverage/` is public so the app can warn while the
    # customer is still picking an address, not at checkout.
    path('coverage/', views.DeliveryCoverageCheckView.as_view(), name='delivery-coverage'),
    path('admin/zones/', views.AdminDeliveryZoneView.as_view(), name='admin-zones'),
    path('admin/zones/<int:pk>/', views.AdminDeliveryZoneDetailView.as_view(), name='admin-zone-detail'),
    path('admin/<int:pk>/zone-from-radius/', views.AdminZoneFromRadiusView.as_view(),
         name='admin-zone-from-radius'),
]
