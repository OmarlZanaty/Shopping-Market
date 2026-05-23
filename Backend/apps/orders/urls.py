from django.urls import path
from . import views
from . import legacy_views as legacy

urlpatterns = [
    # ── Customer order endpoints ────────────────────────────────────────────
    path('', views.CustomerOrderListView.as_view(), name='order-list'),
    path('create/', views.CustomerCreateOrderView.as_view(), name='order-create'),

    # Action endpoints come BEFORE detail/<order_id>/ so they aren't shadowed
    path('<str:order_id>/cancel/', views.CustomerCancelOrderView.as_view(), name='order-cancel'),
    path('<str:order_id>/confirm/', views.CustomerConfirmReceiptView.as_view(), name='order-confirm'),
    path('<str:order_id>/confirm-receipt/', views.CustomerConfirmReceiptView.as_view()),  # back-compat
    path('<str:order_id>/approve-adjustment/', views.CustomerApproveAdjustmentView.as_view(),
         name='order-approve-adjustment'),
    path('<str:order_id>/items/', views.CustomerAddItemView.as_view(), name='order-add-item'),
    path('<str:order_id>/items/<int:item_id>/', views.CustomerRemoveItemView.as_view(),
         name='order-remove-item'),

    # ── Legacy customer aliases (existing Flutter app uses these paths) ─────
    path('<str:order_id>/rate/', legacy.LegacyRateOrderView.as_view(), name='legacy-rate'),
    path('adjustments/<int:adjustment_id>/respond/', legacy.LegacyApproveAdjustmentView.as_view(),
         name='legacy-approve-adjustment'),

    # ── Legacy driver/agent aliases (shared customer+driver Flutter app) ────
    # New canonical paths live under /api/v1/agent/...; these old paths still
    # resolve so the existing client keeps working.
    path('<str:order_id>/accept/', legacy.LegacyDriverAcceptView.as_view(), name='legacy-accept'),
    path('<str:order_id>/start-delivery/', legacy.LegacyDriverStartDeliveryView.as_view(),
         name='legacy-start-delivery'),
    path('<str:order_id>/mark-delivered/', legacy.LegacyDriverMarkDeliveredView.as_view(),
         name='legacy-mark-delivered'),
    path('<str:order_id>/auto-close/', legacy.LegacyDriverAutoCloseView.as_view(),
         name='legacy-auto-close'),
    path('<str:order_id>/items/<int:item_id>/adjust-price/',
         legacy.LegacyDriverAdjustPriceView.as_view(), name='legacy-adjust-price'),
    path('<str:order_id>/items/<int:item_id>/substitute/',
         legacy.LegacyDriverSubstituteView.as_view(), name='legacy-substitute'),
    path('<str:order_id>/add-item/', legacy.LegacyDriverAddItemView.as_view(),
         name='legacy-add-item'),
    path('driver/list/', legacy.LegacyDriverOrderListView.as_view(), name='legacy-driver-list'),

    # Detail (catches anything that isn't a sub-route)
    path('<str:order_id>/', views.CustomerOrderDetailView.as_view(), name='order-detail'),
]
