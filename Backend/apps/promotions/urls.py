from django.urls import path
from . import views

urlpatterns = [
    path('promotions/validate/', views.PromotionValidateView.as_view(), name='promotion-validate'),
    path('admin/promotions/', views.AdminPromotionListCreateView.as_view(), name='admin-promotions'),
    path('admin/promotions/<int:pk>/', views.AdminPromotionDetailView.as_view(), name='admin-promotion-detail'),
    path('admin/delivery-fees/', views.AdminDeliveryFeeListCreateView.as_view(), name='admin-delivery-fees'),
    path('admin/delivery-fees/<int:pk>/', views.AdminDeliveryFeeDetailView.as_view(), name='admin-delivery-fee-detail'),
]
