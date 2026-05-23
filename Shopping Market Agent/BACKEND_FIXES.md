# BACKEND_FIXES.md — Agent app

**Date:** 2026-05-22
**Trigger:** Phase 0 endpoint validation of the Agent app's calls against the Django backend's `API_CONTRACT.md`.

## Spec vs reality

The spec describes a Node/Express/MySQL backend. The actual backend in this repo is **Django + PostgreSQL** at `../Backend/`. All Agent-side endpoints are wired against the Django routes — see `lib/core/constants/api_constants.dart`.

## Mismatches found and fixed

| # | Agent calls | Backend has | Fix |
|---|---|---|---|
| 1 | `POST /auth/login/` | ✅ Already exists (`apps/users/views.LoginView`) | OK |
| 2 | `GET /auth/me/` | ✅ Already exists | OK |
| 3 | `POST /auth/fcm-token/` | ✅ Already exists | OK |
| 4 | `POST /auth/location/` | ✅ Already exists | OK |
| 5 | `GET /agent/orders/` | ✅ `AgentOrderListView` | OK |
| 6 | `GET /agent/orders/<id>/` | ✅ `AgentOrderDetailView` | OK |
| 7 | `PATCH /agent/orders/<id>/accept/` | ✅ `AgentAcceptOrderView` | OK |
| 8 | `PATCH /agent/orders/<id>/start-preparing/` | ✅ `AgentStartPreparingView` | OK |
| 9 | `PATCH /agent/orders/<id>/ready/` | ✅ `AgentMarkReadyView` | OK |
| 10 | `PATCH /agent/orders/<id>/picked-up/` | ✅ `AgentPickedUpView` | OK |
| 11 | `PATCH /agent/orders/<id>/delivered/` | ✅ `AgentDeliveredView` | OK |
| 12 | `PATCH /agent/orders/<id>/force-close/` | ✅ `AgentForceCloseView` | OK |
| 13 | Item ops (`qty`, `unavailable`, `price`, `weight`, `substitute`, `add`, remove) | ✅ All in `apps/orders/agent_views.py` | OK |
| 14 | `GET /agent/inventory/scan/<barcode>/` | ✅ exists | OK |
| 15 | `PATCH /agent/inventory/mark-available/<pid>/` | ✅ exists | OK |
| 16 | `POST /uploads/presign/` (camera proofs) | ✅ `apps/core/upload_views.PresignedUploadView` | OK |
| 17 | `POST /agent/orders/<id>/share/` (audit log when sharing customer data) | ✅ exists | OK |
| 18 | `POST /agent/orders/<id>/log/` (action_type telemetry) | ✅ exists | OK |
| 19 | Envelope shape `{success,data,...}` | ✅ Standard across all endpoints | Handled in `lib/core/network/api_envelope.dart` |
| 20 | WebSocket `/ws/agent/<id>/` | ✅ `apps/orders/consumers.AgentConsumer` | Wired via `AgentWebSocketService` |
| 21 | FCM `data.type=new_order` payload | ✅ `apps/notifications/utils.send_push_notification` sends this | UI overlay in `IncomingOrderOverlay` |

**No backend code changes were needed.** All `/api/v1/agent/*` and `/api/v1/auth/*` endpoints exist and respond with the envelope the Agent app expects.

## Open caveats (not blockers)

- iOS Critical Alerts: requires Apple developer entitlement; without it iOS notifications honour silent/DnD mode.
- Background location 24/7 on Android 14+: implemented via geolocator's foreground stream. For background-during-doze, swap to `flutter_background_geolocation`.
- The shelf-photo `action_type: 'shelf_photo'` flow is wired in API (`OrdersApi.logAction`); UI surfaces it from the camera proof screen.
