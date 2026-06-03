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

# ── Android channel helpers ────────────────────────────────────────────────────
# The customer app registers: 'market_fresh_orders', 'market_fresh_promotions'
# The agent app (preparer/driver) registers: 'agent_new_order', 'agent_adjustment',
#   'agent_general'
# Android 8+ silently drops notifications whose channel_id is not registered on
# the device, so we must send the EXACT channel key the app created — a mismatch
# here makes background/killed-app pushes vanish on Android 8+.

_AGENT_ROLES = frozenset(('preparer', 'driver'))


def _android_channel(user, notif_type: str) -> str:
    """Return the correct Android notification channel for this user + type."""
    role = getattr(user, 'role', '') or ''
    if role in _AGENT_ROLES:
        if notif_type == 'new_order':
            return 'agent_new_order'
        if notif_type in ('order_status', 'adjustment_response',
                          'price_change', 'substitute',
                          'item_added', 'quantity_change'):
            return 'agent_adjustment'
        return 'agent_general'
    # customer / admin / unknown → customer app channels. Promotions/stock use
    # the lighter channel; everything else uses the high-importance orders one.
    if notif_type in ('promotion', 'stock_available'):
        return 'market_fresh_promotions'
    return 'market_fresh_orders'


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


def _clear_token(user):
    """Wipe a dead FCM token so we stop pushing to it; the app re-registers a
    fresh token on its next launch/refresh."""
    try:
        user.fcm_token = ''
        user.save(update_fields=['fcm_token'])
    except Exception:
        pass


def _is_dead_token_error(exc) -> bool:
    """True if the FCM error means the token is permanently invalid."""
    try:
        from firebase_admin import messaging
        if isinstance(exc, messaging.UnregisteredError):
            return True
    except Exception:
        pass
    msg = str(exc).lower()
    return ('registration-token-not-registered' in msg
            or 'requested entity was not found' in msg
            or 'invalid registration' in msg)


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
        channel = _android_channel(user, notif_type)
        message = messaging.Message(
            notification=messaging.Notification(title=title_ar, body=body_ar),
            data=str_data,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='notification_sound',
                    channel_id=channel,
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
        if _is_dead_token_error(e):
            _clear_token(user)
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
        # Determine channel from the first recipient's role (bulk sends are
        # role-homogeneous in practice: all customers or all agents).
        first_user = users[0] if users else None
        channel = _android_channel(first_user, notif_type) if first_user else 'shopping_market_orders'
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title_ar, body=body_ar),
            data=str_data,
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound='notification_sound',
                    channel_id=channel,
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='notification_sound.wav'),
                ),
            ),
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(message)
        # Clear any dead tokens so future sends skip them (responses align 1:1
        # with `users`, which were all guaranteed to have a token above).
        if response.failure_count:
            for idx, resp in enumerate(response.responses):
                if not resp.success and _is_dead_token_error(getattr(resp, 'exception', None)):
                    if idx < len(users):
                        _clear_token(users[idx])
        logger.info('bulk push: %d ok, %d failed', response.success_count, response.failure_count)
        return response.success_count
    except Exception as e:
        logger.warning('bulk push error: %s', e)
        return 0
