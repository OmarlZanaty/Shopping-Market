from django.urls import path
from . import views

urlpatterns = [
    path('', views.RatingCreateView.as_view(), name='rating-create'),
    path('<int:pk>/', views.RatingUpdateView.as_view(), name='rating-update'),
    path('preparer/<uuid:preparer_id>/', views.PreparerRatingsView.as_view(), name='preparer-ratings'),
]
