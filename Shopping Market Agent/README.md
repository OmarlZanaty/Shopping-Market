# Shopping Market — Agent App

Flutter app for two staff roles in the Shopping Market grocery delivery platform:

- **Preparer (Picker)** — picks orders from shelves, handles substitutions / weight diffs / price changes.
- **Delivery Driver** — picks up packed orders, navigates to customers, collects payments, takes proof photos.

Role is decided server-side at login; the app routes accordingly.

---

## Stack

| Layer | Choice |
|---|---|
| State | Riverpod 2.x |
| Routing | go_router 14 |
| HTTP | dio (auth + refresh interceptors) |
| Realtime | web_socket_channel against Django Channels |
| Push | firebase_messaging + awesome_notifications (3 channels, distinct sounds) |
| Storage | flutter_secure_storage (tokens), Hive (cache), sqflite (offline queue) |
| Scanner | mobile_scanner (Google ML Kit) |
| Camera | camera (direct, NOT image_picker) |
| Maps | google_maps_flutter |
| Location | geolocator |

> The spec mentions a Node/Express/MySQL backend, but the actual backend is the Django + PostgreSQL project at `../Backend/`. Endpoints/shapes are wired against that backend. See `BACKEND_FIXES.md`.

---

## Setup

```bash
cd "Shopping Market Agent"
flutter pub get

# Place google-services.json into android/app/ and
# GoogleService-Info.plist into ios/Runner/ (not committed).

flutter run \
  --dart-define=API_BASE_URL=http://YOUR_HOST:8000/api/v1 \
  --dart-define=WS_BASE_URL=ws://YOUR_HOST:8000
```

## Test accounts

```python
# Django shell
from apps.users.models import User
User.objects.create_user(phone='01000000010', password='preparer123',
    full_name='أحمد المحضّر', role=User.Role.PREPARER, branch_id=1)
User.objects.create_user(phone='01000000020', password='driver123',
    full_name='عمر السائق', role=User.Role.DRIVER, branch_id=1)
```

## FCM test payload

```json
{
  "to": "DEVICE_FCM_TOKEN",
  "notification": {"title": "طلب جديد", "body": "ORD-..."},
  "data": {
    "type": "new_order",
    "order_id": "abc-123",
    "order_number": "ORD-20260521-001",
    "item_count": "7",
    "customer_area": "مدينة نصر",
    "total": "245.50"
  },
  "android": {"priority": "high"}
}
```

## Notification sounds

| Channel | Resource | Event |
|---|---|---|
| `agent_new_order`   | `android/app/src/main/res/raw/new_order.mp3` | Loops during overlay |
| `agent_adjustment`  | `android/app/src/main/res/raw/adjustment.mp3` | Customer response |
| `agent_general`     | default | System messages |

## Build APK

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.shopping-market.com/api/v1 \
  --dart-define=WS_BASE_URL=wss://api.shopping-market.com
```

Set up `android/app/key.properties` and signing config in `android/app/build.gradle` — repo doesn't ship a keystore.

## Honest gaps

- iOS Critical Alerts entitlement needed for DnD bypass on iOS.
- Substitute alternative-suggestion 3-tab bottom sheet UI: API wired (`OrdersApi.substitute`), UI deferred.
- Auto-close 2-hour banner: API wired (`OrdersApi.forceClose`), UI deferred.
- Notifications history + profile screens: routes wired, full UIs deferred.
- Background location 24/7: scaffolded with foreground stream (geolocator); for true 24/7 background on Android 14+, swap to `flutter_background_geolocation`.
