from django.urls import path
from . import views

urlpatterns = [
    path('', views.BranchListView.as_view(), name='branches'),
    path('admin/', views.AdminBranchView.as_view(), name='admin-branches'),
    path('admin/<int:pk>/', views.AdminBranchDetailView.as_view(), name='admin-branch-detail'),
    path('admin/<int:pk>/status/', views.AdminBranchStatusToggleView.as_view(), name='admin-branch-status'),
]
