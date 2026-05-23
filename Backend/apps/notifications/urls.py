from django.urls import path
from . import views

urlpatterns = [
    path('settings/', views.AppSettingsPublicView.as_view(), name='app-settings'),
    path('admin/settings/', views.AdminAppSettingsView.as_view(), name='admin-settings'),
    path('admin/settings/bulk/', views.AdminAppSettingsBulkView.as_view(), name='admin-settings-bulk'),
    path('admin/settings/<int:pk>/', views.AdminAppSettingDetailView.as_view(), name='admin-setting-detail'),
    path('my/', views.MyNotificationsView.as_view(), name='my-notifications'),
    path('<int:pk>/read/', views.MarkNotificationReadView.as_view(), name='mark-read'),
    path('read-all/', views.MarkAllNotificationsReadView.as_view(), name='mark-all-read'),
    path('admin/send/', views.AdminSendNotificationView.as_view(), name='admin-send-notification'),
]
