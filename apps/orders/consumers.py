"""
WebSocket consumers (Django Channels).

Rooms:
- order_{order_number}     — per-order updates (customer + assigned agents)
- admin_dashboard          — global admin feed
- store_admin_{store_id}   — per-store admin feed (Store Admin only sees their store)
- driver_{driver_id}       — driver-specific alerts
"""
import json
from urllib.parse import parse_qs

from channels.generic.websocket import AsyncWebsocketConsumer


def _qs_token(scope):
    qs = parse_qs(scope.get('query_string', b'').decode('utf-8', errors='ignore'))
    token = (qs.get('token') or [None])[0]
    return token


class OrderTrackingConsumer(AsyncWebsocketConsumer):
    """Real-time order status + driver location for a single order."""

    async def connect(self):
        self.order_id = self.scope['url_route']['kwargs']['order_id']
        self.group_name = f'order_{self.order_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        # Read-only stream — ignore client messages
        return

    async def order_update(self, event):
        await self.send(text_data=json.dumps({
            'event': 'order:status_changed',
            'status': event['status'],
            'driver_lat': event.get('driver_lat'),
            'driver_lng': event.get('driver_lng'),
            'message_ar': event.get('message_ar', ''),
            'message_en': event.get('message_en', ''),
        }))

    async def order_item_adjusted(self, event):
        await self.send(text_data=json.dumps({
            'event': 'order:item_adjusted',
            **event,
        }))

    async def driver_location(self, event):
        await self.send(text_data=json.dumps({
            'event': 'driver:location',
            'latitude': event['latitude'],
            'longitude': event['longitude'],
        }))


class AdminDashboardConsumer(AsyncWebsocketConsumer):
    """Global admin dashboard feed."""

    async def connect(self):
        self.group_name = 'admin_dashboard'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        return

    async def new_order(self, event):
        await self.send(text_data=json.dumps({'event': 'order:new', **event}))

    async def order_status_changed(self, event):
        await self.send(text_data=json.dumps({'event': 'order:status_changed', **event}))

    async def driver_location_update(self, event):
        await self.send(text_data=json.dumps({'event': 'driver:location', **event}))

    async def product_availability_changed(self, event):
        await self.send(text_data=json.dumps({'event': 'product:availability_changed', **event}))


class StoreAdminConsumer(AsyncWebsocketConsumer):
    """Per-store admin feed — only events scoped to this store."""

    async def connect(self):
        self.store_id = self.scope['url_route']['kwargs']['store_id']
        self.group_name = f'store_admin_{self.store_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        return

    async def order_status_changed(self, event):
        await self.send(text_data=json.dumps({'event': 'order:status_changed', **event}))


class DriverConsumer(AsyncWebsocketConsumer):
    """Per-driver alerts."""

    async def connect(self):
        self.driver_id = self.scope['url_route']['kwargs']['driver_id']
        self.group_name = f'driver_{self.driver_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data):
        return

    async def new_order_alert(self, event):
        await self.send(text_data=json.dumps({'event': 'order:new', **event}))

    async def adjustment_response(self, event):
        await self.send(text_data=json.dumps({'event': 'adjustment:response', **event}))


class NotificationConsumer(AsyncWebsocketConsumer):
    """Per-user notification stream."""

    async def connect(self):
        self.user_id = self.scope['url_route']['kwargs']['user_id']
        self.group_name = f'user_{self.user_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def notification_new(self, event):
        await self.send(text_data=json.dumps({'event': 'notification:new', **event}))
