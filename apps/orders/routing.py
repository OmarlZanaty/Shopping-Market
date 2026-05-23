from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'ws/order/(?P<order_id>[\w-]+)/$', consumers.OrderTrackingConsumer.as_asgi()),
    re_path(r'ws/admin/$', consumers.AdminDashboardConsumer.as_asgi()),
    re_path(r'ws/admin/store/(?P<store_id>\d+)/$', consumers.StoreAdminConsumer.as_asgi()),
    re_path(r'ws/driver/(?P<driver_id>[\w-]+)/$', consumers.DriverConsumer.as_asgi()),
    re_path(r'ws/user/(?P<user_id>[\w-]+)/$', consumers.NotificationConsumer.as_asgi()),
]
