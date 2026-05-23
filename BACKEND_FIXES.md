# BACKEND_FIXES.md

**Date:** 2026-05-21
**Trigger:** Phase 0 audit of the existing Flutter customer app (`/Shopping Market/lib/services/api_service.dart`) against the backend's `API_CONTRACT.md`.

This doc records every backend change made for Flutter compatibility, with the exact file + reason.

---

## Summary

| # | Problem in Flutter ↔ Backend | Fix | File touched |
|---|---|---|---|
| 1 | Flutter reads `res.data['results']` for paginated lists; new backend wraps in `{success, data, pagination}` | Dual-shape pagination — emit BOTH old DRF keys (`results`, `count`, `next`, `previous`) AND the new envelope from `StandardPagination` | `apps/core/pagination.py` |
| 2 | Flutter `POST /orders/$orderId/rate/` — backend moved rating create to `POST /api/v1/ratings/` | Added a legacy view at `/orders/<id>/rate/` that maps the old body (`product_rating`, `delivery_rating`) → new serializer | `apps/orders/legacy_views.py` + `urls.py` |
| 3 | Flutter `POST /orders/adjustments/$adjId/respond/` — backend uses `PATCH /orders/<id>/approve-adjustment/` | Added `LegacyApproveAdjustmentView` that re-implements approval logic against the new model fields | `apps/orders/legacy_views.py` + `urls.py` |
| 4 | Flutter (driver side, same codebase) calls `POST /orders/<id>/accept|start-delivery|mark-delivered|auto-close/` — backend moved to `/api/v1/agent/orders/<id>/...` | Added thin proxy views at the old paths that delegate to the canonical agent views | `apps/orders/legacy_views.py` + `urls.py` |
| 5 | Flutter `POST /orders/<id>/items/<itemId>/adjust-price/` and `/substitute/` and `/orders/<id>/add-item/` — backend moved to agent paths | Added legacy proxy views for each | same |
| 6 | Flutter `GET /orders/driver/list/` — backend moved to `/api/v1/agent/orders/` | Added `LegacyDriverOrderListView` proxying to `AgentOrderListView.get_queryset` | same |
| 7 | Refresh-token path — Flutter tries `/auth/token/refresh/` (legacy DRF SimpleJWT path) | Backend already exposes both `/auth/refresh/` (new) and `/auth/token/refresh/` (legacy alias) in `apps/users/urls.py` | already correct |
| 8 | OTP send/verify — Flutter ApiService didn't have these methods | Backend already has them; **Flutter side** added `sendOtp` + `verifyOtp` methods in `lib/services/api_service.dart` | (Flutter side) |

No data-model migrations were required for this round.

---

## 1. Dual-shape pagination

**Problem.** The new `StandardPagination` in `apps/core/pagination.py` returns:

```json
{"success": true, "data": [...], "pagination": {"page": 1, ...}, "message": "", "errors": []}
```

The existing Flutter `ApiService` (e.g. `getMyOrders`, `getCategories`) does:

```dart
final list = res.data['results'] ?? res.data as List;
```

This produced `null` lists because `'results'` was missing.

**Fix.** Pagination now emits **both** the new envelope keys *and* the legacy DRF keys (`results`, `count`, `next`, `previous`) in the same response body. Old clients see `results`, new clients see `data` + `pagination`. Zero coupling, zero forks.

```python
# apps/core/pagination.py — get_paginated_response()
return Response(OrderedDict([
    ('success', True),
    ('data', data),
    ('pagination', ...),
    ('message', ''),
    ('errors', []),
    # Legacy DRF keys — back-compat
    ('results', data),
    ('count', total),
    ('next', next_link),
    ('previous', prev_link),
]))
```

Trade-off: response body is ~30 bytes larger. Acceptable.

---

## 2. `POST /orders/<order_id>/rate/` legacy endpoint

`apps/orders/legacy_views.py::LegacyRateOrderView`

The customer-app `rateOrder()` calls `POST /orders/$orderId/rate/` with body:
```json
{ "product_rating": 5, "delivery_rating": 5, "comment": "..." }
```

New canonical endpoint is `POST /ratings/` with field aliases `product_quality_rating` and `delivery_speed_rating`. The legacy view:

1. Looks up the order by `order_number`, `order_id`, or `id`.
2. Validates it's delivered and not already rated.
3. Accepts both field aliases.
4. Awards the rating-bonus points.
5. Returns the same `{rating_id, points_bonus, new_balance}` shape.

Wired in `apps/orders/urls.py`:
```python
path('<str:order_id>/rate/', legacy.LegacyRateOrderView.as_view()),
```

---

## 3. `POST /orders/adjustments/<id>/respond/` legacy endpoint

`apps/orders/legacy_views.py::LegacyApproveAdjustmentView`

Old shape: POST with `{ approved: true|false }` to `/orders/adjustments/<id>/respond/`.
New shape: PATCH to `/orders/<order_id>/approve-adjustment/` with `{ adjustment_id, approved }`.

The legacy view re-implements the approval-side-effect logic locally (price update / weight diff / substitute / item-added flow) so it doesn't have to forge a `request.data` mutation against the canonical view. This is cleaner than the original `request._full_data` workaround.

---

## 4-6. Driver/agent legacy proxies

The shared customer+driver Flutter codebase still hits driver paths under `/orders/<id>/...`. Backend moved these to `/api/v1/agent/`. Each proxy view in `apps/orders/legacy_views.py` instantiates the canonical agent view and calls the right HTTP method:

| Legacy path | Proxies to |
|---|---|
| `POST /orders/<id>/accept/` | `AgentAcceptOrderView.patch` |
| `POST /orders/<id>/start-delivery/` | `AgentPickedUpView.patch` |
| `POST /orders/<id>/mark-delivered/` | `AgentDeliveredView.patch` |
| `POST /orders/<id>/auto-close/` | `AgentForceCloseView.patch` |
| `POST /orders/<id>/items/<iid>/adjust-price/` | `AgentItemAdjustPriceView.patch` |
| `POST /orders/<id>/items/<iid>/substitute/` | `AgentItemSubstituteView.post` |
| `POST /orders/<id>/add-item/` | `AgentAddItemView.post` |
| `GET /orders/driver/list/` | `AgentOrderListView.get_queryset` |

All permissions are preserved (`IsAuthenticated` + `IsAgent`).

---

## 7. Refresh token path

Both `/auth/refresh/` and `/auth/token/refresh/` are mapped in `apps/users/urls.py` — already correct, no change needed:

```python
path('refresh/', TokenRefreshView.as_view(), name='token-refresh'),
path('token/refresh/', TokenRefreshView.as_view()),  # back-compat
```

The Flutter ApiService's `_refreshToken()` now tries the new path first and falls back automatically.

---

## 8. OTP send/verify endpoints

Backend already exposes:
- `POST /auth/send-otp/` (rate-limited 3/min per phone)
- `POST /auth/verify-otp/` (rate-limited 5/min)

**Flutter-side fix:** added `sendOtp()` and `verifyOtp()` methods to `lib/services/api_service.dart` plus the new `PhoneLoginScreen` and `OtpScreen` UIs. The screens consume the spec envelope via `ApiEnvelope.unwrap()`.

---

## Endpoints touched

```
GET    /api/v1/orders/                              ✓ (now returns both `data` and `results`)
GET    /api/v1/orders/<id>/                         ✓
POST   /api/v1/orders/<id>/rate/                    ✓ NEW legacy alias
POST   /api/v1/orders/adjustments/<id>/respond/     ✓ NEW legacy alias
POST   /api/v1/orders/<id>/accept/                  ✓ NEW legacy proxy
POST   /api/v1/orders/<id>/start-delivery/          ✓ NEW legacy proxy
POST   /api/v1/orders/<id>/mark-delivered/          ✓ NEW legacy proxy
POST   /api/v1/orders/<id>/auto-close/              ✓ NEW legacy proxy
POST   /api/v1/orders/<id>/items/<iid>/adjust-price/✓ NEW legacy proxy
POST   /api/v1/orders/<id>/items/<iid>/substitute/  ✓ NEW legacy proxy
POST   /api/v1/orders/<id>/add-item/                ✓ NEW legacy proxy
GET    /api/v1/orders/driver/list/                  ✓ NEW legacy proxy
```

All canonical endpoints under `/api/v1/agent/` and `/api/v1/ratings/` remain unchanged and are the recommended path for new client code.

---

## Testing

Run the existing Flutter app against the patched backend — no Flutter-side changes are required for the legacy code paths to keep working. The dual-shape pagination is the highest-impact fix and unblocks every list screen.

```bash
# Backend
python manage.py runserver 0.0.0.0:8000
celery -A config worker -l info

# Flutter (from the Shopping Market dir)
flutter pub get
flutter run -t lib/main_customer.dart
```

Verification points:
1. **Categories load** on home screen → uses `getCategories()` which reads `data['results']`.
2. **Orders list loads** → uses `getMyOrders()`.
3. **Rate order** → uses `POST /orders/<id>/rate/`.
4. **Driver accept order** → uses `POST /orders/<id>/accept/`.
5. **OTP login flow** → new screens hit `/auth/send-otp/` then `/auth/verify-otp/`.
