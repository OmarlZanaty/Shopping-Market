from django.urls import path
from . import views

urlpatterns = [
    path('adjustment-topup/', views.InitiateAdjustmentPaymentView.as_view(), name='adjustment-topup'),
    path('webhook/paymob/', views.PaymobWebhookView.as_view(), name='paymob-webhook'),
]
