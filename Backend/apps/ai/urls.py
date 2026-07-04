from django.urls import path
from . import views

urlpatterns = [
    path('recommendations/', views.RecommendationsView.as_view(), name='ai-recommendations'),
    path('smart-cart/', views.SmartCartView.as_view(), name='ai-smart-cart'),
    path('visual-search/', views.VisualSearchView.as_view(), name='ai-visual-search'),
]
