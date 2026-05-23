# TESTING_CHECKLIST.md — Agent app

Mirrors the spec's testing checklist. Each item is marked **PASS** (code-reviewed), **PARTIAL** (subset implemented), **RUNTIME-PENDING** (needs device + live backend), or **DEFERRED** (out of one-shot scope).

| # | Spec item | Status | Reference |
|---|---|---|---|
| 1 | Backend endpoints: all `/api/agent/*` respond | **PASS** | See `BACKEND_FIXES.md` |
| 2 | Login preparer → preparer UI; login driver → driver UI | **PASS** | `features/home/presentation/role_gate.dart` dispatches on `AgentRole` |
| 3 | Incoming order: full-screen overlay, looping sound, countdown, accept/reject | **PASS** | `features/orders/presentation/incoming_order_overlay.dart` |
| 4 | Sound plays under silent mode (with permission) | **PARTIAL** | Android: `criticalAlerts: true` set; iOS: requires Apple entitlement |
| 5 | Order list: real-time new orders without refresh | **PARTIAL** | FCM push wired; WebSocket subscription scaffold in `AgentWebSocketService` but not yet bound to list invalidation |
| 6 | Picking: checkbox, stepper, scan-to-pick | **PASS** | `features/orders/presentation/picking_screen.dart` |
| 7 | Unavailable flow + 3-tab alternative picker + 15-min timer | **PARTIAL** | API wired (`markUnavailable`, `substitute`); 3-tab bottom sheet UI deferred |
| 8 | Weight diff: calculation + customer notify + approve/reject | **PARTIAL** | API wired (`setActualWeight`); approval flow lives in backend FCM + customer app |
| 9 | Price change: notify + approval | **PASS** | Price-edit bottom sheet in `picking_screen.dart` |
| 10 | Add item to order: customer approval flow | **PARTIAL** | API wired (`OrdersApi.addItem`); search sheet UI deferred |
| 11 | Share customer data: formatted message + maps URL + log | **PASS** | `OrderDetailScreen._shareCustomerData` |
| 12 | Camera proof: photo + watermark + upload | **PARTIAL** | Capture + S3 presign + upload wired; canvas watermark step deferred |
| 13 | Delivery confirm: amount validation + photo required | **PASS** | `delivery_confirm_screen.dart` |
| 14 | Auto-close 2h: timer triggers, photo required | **PARTIAL** | API wired (`OrdersApi.forceClose`); banner UI deferred |
| 15 | Location tracking: 5-s interval, 15-s throttled | **PASS** | `core/services/location_service.dart` |
| 16 | Offline: accept order, lose wifi, restore, sync | **PARTIAL** | `OfflineQueue` SQLite scaffold ready; sync worker deferred |
| 17 | All colors match spec hex values | **PASS** | `core/constants/app_colors.dart` matches spec exactly |
| 18 | RTL: Arabic right-aligned, icons mirrored | **PASS** | `MaterialApp` wrapped in `Directionality(textDirection: rtl)` |
| 19 | Memory: 20+ orders without leak | **RUNTIME-PENDING** | DevTools profile needed on device |

## How to run + verify

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://<your-host>:8000/api/v1 \
  --dart-define=WS_BASE_URL=ws://<your-host>:8000
```

Create test accounts via Django shell (see README), then:

1. Login as preparer (`01000000010` / `preparer123`) → preparer home with 3 tabs.
2. Login as driver (`01000000020` / `driver123`) → driver home + location-permission prompt.
3. From admin dashboard or backend tools, push an FCM with `data.type=new_order` to the device → IncomingOrderOverlay appears.

## Honest deferred items

These need iteration to finish but don't block the app from running and most workflows from completing:

- 3-tab alternative-product bottom sheet (AI suggestions / barcode / name search)
- 15-min customer-approval countdown timer on the item rows
- Auto-close 2-hour banner on driver order detail
- Notification History full UI
- Profile screen + cash reconciliation submission UI
- Watermarking the captured camera photo with order number + timestamp (using `package:image`)
- Sync worker that drains `OfflineQueue` on `connectivity_plus` reconnect
- iOS Critical Alerts entitlement
