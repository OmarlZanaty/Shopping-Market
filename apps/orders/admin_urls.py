from django.urls import path
from . import admin_views as v

urlpatterns = [
    path('orders/', v.AdminOrderListView.as_view(), name='admin-orders'),
    path('orders/live/', v.AdminOrdersLiveView.as_view(), name='admin-orders-live'),
    path('orders/<str:order_id>/', v.AdminOrderDetailView.as_view(), name='admin-order-detail'),
    path('orders/<str:order_id>/assign-preparer/', v.AdminAssignPreparerView.as_view(),
         name='admin-assign-preparer'),
    path('orders/<str:order_id>/assign-driver/', v.AdminAssignDriverView.as_view(),
         name='admin-assign-driver'),
    path('orders/<str:order_id>/cancel/', v.AdminCancelOrderView.as_view(), name='admin-cancel-order'),
    path('orders/<str:order_id>/return/', v.AdminReturnOrderView.as_view(), name='admin-return-order'),
    path('tracking/drivers/', v.AdminTrackingDriversView.as_view(), name='admin-tracking-drivers'),
]
