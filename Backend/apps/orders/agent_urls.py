from django.urls import path
from . import agent_views as v

urlpatterns = [
    # Order list / detail
    path('orders/', v.AgentOrderListView.as_view(), name='agent-orders'),
    path('orders/<str:order_id>/', v.AgentOrderDetailView.as_view(), name='agent-order-detail'),

    # Lifecycle transitions
    path('orders/<str:order_id>/accept/', v.AgentAcceptOrderView.as_view(), name='agent-accept'),
    path('orders/<str:order_id>/reject/', v.AgentRejectOrderView.as_view(), name='agent-reject'),
    path('orders/<str:order_id>/start-preparing/', v.AgentStartPreparingView.as_view(), name='agent-start-preparing'),
    path('orders/<str:order_id>/ready/', v.AgentReadyView.as_view(), name='agent-ready'),
    path('orders/<str:order_id>/picked-up/', v.AgentPickedUpView.as_view(), name='agent-picked-up'),
    path('orders/<str:order_id>/delivered/', v.AgentDeliveredView.as_view(), name='agent-delivered'),
    path('orders/<str:order_id>/force-close/', v.AgentForceCloseView.as_view(), name='agent-force-close'),

    # Item-level actions
    path('orders/<str:order_id>/items/add/', v.AgentAddItemView.as_view(), name='agent-add-item'),
    path('orders/<str:order_id>/items/<int:item_id>/qty/', v.AgentItemAdjustQtyView.as_view(),
         name='agent-item-qty'),
    path('orders/<str:order_id>/items/<int:item_id>/unavailable/', v.AgentItemUnavailableView.as_view(),
         name='agent-item-unavailable'),
    path('orders/<str:order_id>/items/<int:item_id>/price/', v.AgentItemAdjustPriceView.as_view(),
         name='agent-item-price'),
    path('orders/<str:order_id>/items/<int:item_id>/weight/', v.AgentItemAdjustWeightView.as_view(),
         name='agent-item-weight'),
    path('orders/<str:order_id>/items/<int:item_id>/substitute/', v.AgentItemSubstituteView.as_view(),
         name='agent-item-substitute'),
    path('orders/<str:order_id>/items/<int:item_id>/', v.AgentRemoveItemView.as_view(),
         name='agent-item-remove'),

    # Inventory
    path('inventory/products/', v.AgentInventoryListView.as_view(), name='agent-inventory-products'),
    path('inventory/scan/<str:barcode>/', v.AgentInventoryScanView.as_view(), name='agent-inventory-scan'),
    path('inventory/mark-available/<uuid:product_id>/', v.AgentMarkAvailableView.as_view(),
         name='agent-inventory-mark-available'),
    path('inventory/toggle/<uuid:product_id>/', v.AgentToggleAvailabilityView.as_view(),
         name='agent-inventory-toggle'),

    # Action log + share
    path('orders/<str:order_id>/log/', v.AgentActionLogView.as_view(), name='agent-action-log'),
    path('orders/<str:order_id>/share/', v.AgentShareCustomerDataView.as_view(), name='agent-share'),

    # Location (forward to user view — also reachable at /auth/location/)
    path('location/', __import__('apps.users.views', fromlist=['UpdateLocationView']).UpdateLocationView.as_view(),
         name='agent-location'),
]
