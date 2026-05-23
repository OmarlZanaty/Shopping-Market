from django.urls import path
from . import views

urlpatterns = [
    path('', views.CategoryListView.as_view(), name='category-list'),
    path('<int:pk>/products/', views.CategoryProductsView.as_view(), name='category-products'),
]
