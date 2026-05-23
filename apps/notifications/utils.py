"""
Push notification helpers.

Every push:
- Persists to InAppNotification for in-app inbox.
- Sends via FCM if user.fcm_token is set.
- Emits a WebSocket event so the receiving app can react in real time.

The function never raises — it logs and returns False on failure.
"""
import logging
from django.conf import settings

from .models import InAppNotification

logger = logging.getLogger(__name__)


def _persist_in_app(user, title_ar, title_en, body_ar, body_en, notif_type, data):
    try:
        InAppNotification.objects.create(
            user=user,
            title_ar=title_ar or '',
            title_en=title_en or '',
            body_ar=body_ar or '',
            body_en=body_en or '',
            type=notif_type if notif_type else 'general',
            data=data or {},
        )
    except Exception as e:
        logger.exception('in-app persist error for %s: %s', getattr(user, 'phone', '?'), e)


def _emit_ws_notification(user, payload):
    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync
        layer = get_channel_layer()
        if not layer:
            return
        async_to_sync(layer.group_send)(
            f'user_{user.id}',
            {'type': 'notification_new', **payload},
        )
    except Exception:
        pass


def send_push_notification(user, title_ar, title_en, body_ar, body_en, data=None):
    """Single push. Returns True on FCM success, False otherwise."""
    if user is None:
        return False
    data = data or {}
    notif_type = data.get('type', 'general')

    _persist_in_app(user, title_ar, title_en, body_ar, body_en, notif_type, data)
    _emit_ws_notification(user, {
        'title_ar': title_ar, 'title_en': title_en,
        'body_ar': body_ar, 'body_en': body_en,
        'data': data, 'type': notif_type,
    })

    if not getattr(user, 'fcm_token', None):
        return False

    try:
        import firebase_admin
        from firebase_admin import messaging, credentials
        if not firebase_admin._apps:
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
            firebase_admin.initialize_app(cred)
        # FCM data values must all be strings
        str_data = {k: str(v) for k, v in {
            'title_ar': title_ar or '',
            'title_en': title_en or '',
            'body_ar': body_ar or '',
            'body_en': body_en or '',
            'type': notif_type,
            **data,
        }.items()}
        message = messaging.Message(
            notification=messaging.Notification(title=title_ar, body=body_ar),
            data=str_data,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='notification_sound',
                    channel_id='shopping_market_orders',
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='notification_sound.wav'),
                ),
            ),
            token=user.fcm_token,
        )
        messaging.send(message)
        # Don't log phone in production
        if settings.DEBUG:
            logger.debug('push sent to %s', user.phone)
        return True
    except Exception as e:
        logger.warning('push error for user %s: %s', user.id, e)
        return False


def send_bulk_push(users_qs, title_ar, title_en, body_ar, body_en, data=None):
    """Bulk push via FCM multicast. Persists in-app for every user too."""
    data = data or {}
    notif_type = data.get('type', 'general')

    users = list(users_qs.exclude(fcm_token='').exclude(fcm_token__isnull=True))
    # Persist in-app for everyone (even those without FCM tokens)
    for u in users_qs:
        _persist_in_app(u, title_ar, title_en, body_ar, body_en, notif_type, data)
        _emit_ws_notification(u, {
            'title_ar': title_ar, 'title_en': title_en,
            'body_ar': body_ar, 'body_en': body_en,
            'data': data, 'type': notif_type,
        })

    tokens = [u.fcm_token for u in users if u.fcm_token]
    if not tokens:
        return 0
    try:
        import firebase_admin
        from firebase_admin import messaging, credentials
        if not firebase_admin._apps:
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
            firebase_admin.initialize_app(cred)
        str_data = {k: str(v) for k, v in {
            'title_ar': title_ar or '',
            'title_en': title_en or '',
            'body_ar': body_ar or '',
            'body_en': body_en or '',
            'type': notif_type,
            **data,
        }.items()}
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title_ar, body=body_ar),
            data=str_data,
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(message)
        logger.info('bulk push: %d ok, %d failed', response.success_count, response.failure_count)
        return response.success_count
    except Exception as e:
        logger.warning('bulk push error: %s', e)
        return 0
