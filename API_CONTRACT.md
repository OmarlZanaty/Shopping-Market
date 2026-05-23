# API CONTRACT — Shopping Market Backend

**Base URL:** `https://api.shopping-market.com`
**Versioned base:** `/api/v1/...` (plus spec-shape aliases under `/api/...` where requested in the prompt).
**Auth header:** `Authorization: Bearer <access_token>` unless marked **public**.

**Standard response envelope** (every endpoint):

```json
{ "success": true, "data": { ... }, "message": "", "errors": [] }
```

**List endpoints add a `pagination` block:**

```json
{
  "success": true,
  "data": [ ... ],
  "pagination": { "page": 1, "limit": 20, "total": 134, "totalPages": 7 },
  "message": "",
  "errors": []
}
```

**Error envelope:**

```json
{ "success": false, "data": {}, "message": "Invalid input", "errors": [{ "field": "phone", "message": "..." }] }
```

---

## 1. Auth — `/api/v1/auth/` (also `/api/auth/`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| POST | `/send-otp/` | public | `{ phone }` | `{ sent, expires_in_seconds, debug_code? }` — **3/min** per phone |
| POST | `/verify-otp/` | public | `{ phone, code, full_name?, fcm_token? }` | `{ access, refresh, user, is_new_user }` — **5/min** per phone |
| POST | `/login/` | public | `{ phone, password }` | `{ access, refresh, user }` — staff only; customers must use OTP |
| POST | `/refresh/` | public | `{ refresh }` | `{ access, refresh }` — rotates refresh token |
| POST | `/logout/` | required | `{ refresh }` | `{ logged_out: true }` — blacklists refresh |
| POST | `/social/` | public | `{ provider, token, social_id, full_name?, email?, phone? }` | `{ access, refresh, user, is_new_user }` |
| GET | `/me/` | required | — | full user profile |
| PATCH | `/me/` | required | `{ full_name?, email?, fcm_token?, avatar? }` | updated profile |
| POST | `/biometric/register/` | required | `{ biometric_token }` | `{ registered: true }` |
| POST | `/biometric/login/` | public | `{ biometric_token }` | `{ access, refresh, user }` |
| POST | `/fcm-token/` | required | `{ fcm_token }` | `{ fcm_token_updated: true }` |
| PATCH/POST | `/location/` | agent | `{ lat, lng }` | `{ updated: true }` — **max 1/5s** |

JWT lifetimes: **15-min access**, **30-day refresh**. Refresh tokens rotated and blacklisted on use.

---

## 2. Stores — `/api/v1/stores/` (also `/api/stores/`)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/config/` | public | `{ multistore_enabled: bool, default_store_id: int|null }`. Customer app calls on launch. |
| GET | `/` | public | List active stores **only** when `multistore_enabled=1`. Returns 404 otherwise. |
| GET | `/<id>/` | public | Store detail; `?lat=&lng=` returns nearest branch. |
| GET | `/admin/all/` | super-admin | All stores + stats. **store_id IS NULL required.** |
| POST | `/admin/all/` | super-admin | Create store. |
| PATCH/DELETE | `/admin/<id>/` | super-admin | Update / delete. |
| PATCH | `/admin/<id>/status/` | super-admin | Toggle is_active. |
| PATCH | `/admin/reorder/` | super-admin | Body: `[{id, sort_order}]`. |
| GET / PATCH | `/admin/settings/multistore/` | super-admin | `{ multistore_enabled, default_store_id }`. |

---

## 3. Products — `/api/v1/products/`

### Customer / public

| Method | Path | Notes |
|---|---|---|
| GET | `/` | `?store_id=&category_id=&branch_id=&search=&is_available=&has_discount=&page=&limit=` |
| GET | `/search/` | Full search with pagination |
| GET | `/search/suggestions/` | `?q=` typeahead — first 10 |
| GET | `/barcode/<barcode>/` | Public barcode lookup |
| GET | `/<uuid>/` | Detail w/ images, categories, alternatives, related, waitlist_count |
| GET | `/categories/` | List visible categories (5-min Redis cache) |
| GET | `/banners/` | Active banners only |
| POST | `/banners/<id>/click/` | Track click — atomic increment |
| POST | `/waitlist/` | Body: `{ product_id }` |
| DELETE | `/waitlist/<uuid>/` | Unsubscribe |

### Admin (store-scoped automatically)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET / POST | `/admin/products/` | admin/branch_manager | List / create |
| GET / PATCH / DELETE | `/admin/products/<uuid>/` | admin/branch_manager | DELETE = soft delete (is_available=0) |
| PATCH | `/admin/products/<uuid>/availability/` | admin/branch_manager | Toggle + WS event |
| POST | `/admin/products/bulk/` | admin/branch_manager | Body: `{ action, product_ids, payload }` |
| POST | `/admin/products/import/` | admin/branch_manager | multipart `file` — queued to Celery |
| GET | `/admin/products/<uuid>/waitlist/` | admin/branch_manager | Who's waiting |
| POST | `/admin/products/<uuid>/notify-waitlist/` | admin/branch_manager | Trigger push |

---

## 4. Categories — `/api/v1/categories/`

| Method | Path | Notes |
|---|---|---|
| GET | `/` | All visible, store-filtered via `?store_id=` |
| GET | `/<id>/products/` | Paginated products in category |
| Admin: `/admin/categories/` on products app (CRUD + reorder) | | |

---

## 5. Orders (customer) — `/api/v1/orders/`

| Method | Path | Notes |
|---|---|---|
| GET | `/` | Customer's orders, newest first |
| POST | `/create/` | Body: `{ address_id, items:[{product_id, qty}], payment_method, notes?, promo_code?, points_to_use? }`. Race-safe `ORD-YYYYMMDD-NNN` numbering via SELECT FOR UPDATE. |
| GET | `/<order_id>/` | Detail — items, adjustments, timestamps |
| PATCH | `/<order_id>/cancel/` | Allowed: new\|accepted\|preparing. Restores stock, refunds wallet+points. |
| PATCH | `/<order_id>/confirm/` | Customer confirms delivery. Awards loyalty points. |
| PATCH | `/<order_id>/approve-adjustment/` | Body: `{ adjustment_id, approved }` |
| POST | `/<order_id>/items/` | Add item (preparing only) |
| DELETE | `/<order_id>/items/<item_id>/` | Remove item (preparing only) |

---

## 6. Agent (preparer + driver) — `/api/v1/agent/`

All require `role IN ('preparer','driver')`. Store-scoped via `user.store_id`.

### Orders

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/orders/` | agent | Assigned + unassigned pool, by status |
| GET | `/orders/<order_id>/` | agent | Full detail + adjustments |
| PATCH | `/orders/<order_id>/accept/` | agent | new → accepted |
| PATCH | `/orders/<order_id>/reject/` | agent | Clears assignment, status → new |
| PATCH | `/orders/<order_id>/start-preparing/` | preparer | accepted → preparing |
| PATCH | `/orders/<order_id>/ready/` | preparer | preparing → out_for_delivery |
| PATCH | `/orders/<order_id>/picked-up/` | driver | Driver claims order |
| PATCH | `/orders/<order_id>/delivered/` | driver | Body: `{ amount_collected?, delivery_photo_url?, proof_image? }`. Triggers 2-hr auto-close. |
| PATCH | `/orders/<order_id>/force-close/` | driver | After 2hr only. Requires `delivery_photo_url`. |

### Item actions

| Method | Path | Body |
|---|---|---|
| PATCH | `/orders/<oid>/items/<iid>/qty/` | `{ actual_qty, reason? }` |
| PATCH | `/orders/<oid>/items/<iid>/unavailable/` | — |
| PATCH | `/orders/<oid>/items/<iid>/price/` | `{ new_price, reason? }` |
| PATCH | `/orders/<oid>/items/<iid>/weight/` | `{ weight_actual, reason? }` |
| POST | `/orders/<oid>/items/<iid>/substitute/` | `{ substitute_product_id, reason? }` |
| POST | `/orders/<oid>/items/add/` | `{ product_id, qty, reason? }` |
| DELETE | `/orders/<oid>/items/<iid>/` | — |

Each adjustment that needs customer approval (price/weight/substitute/item_added) starts a Celery 15-min timer. On timeout the agent receives a `call_customer` push.

### Inventory / log / share

| Method | Path | Notes |
|---|---|---|
| GET | `/inventory/scan/<barcode>/` | Returns product + store-scoped stock |
| PATCH | `/inventory/mark-available/<uuid>/` | Restock; triggers waitlist push |
| POST / GET | `/orders/<oid>/log/` | Action log: POST `{ action_type, data? }` |
| POST | `/orders/<oid>/share/` | Returns `{ text, maps_url, whatsapp_url }` + logs share |
| PATCH | `/location/` | `{ lat, lng }` — **1/5s rate** |

---

## 7. Admin orders — `/api/v1/admin/`

| Method | Path | Notes |
|---|---|---|
| GET | `/orders/` | Filters: `status, payment_method, branch, store, from_date, to_date, search` |
| GET | `/orders/live/` | Counts per status — dashboard cards |
| GET | `/orders/<oid>/` | Full detail |
| PATCH | `/orders/<oid>/assign-preparer/` | `{ preparer_id }` |
| PATCH | `/orders/<oid>/assign-driver/` | `{ driver_id }` |
| PATCH | `/orders/<oid>/cancel/` | `{ reason }` mandatory — processes refund |
| POST | `/orders/<oid>/return/` | `{ items:[{item_id, qty, condition}], refund_method }` |
| GET | `/tracking/drivers/` | Live driver positions (Redis-backed) |

---

## 8. Addresses — `/api/v1/auth/addresses/`

| Method | Path | Notes |
|---|---|---|
| GET / POST | `/addresses/` | List / add |
| PATCH / DELETE | `/addresses/<id>/` | Update / delete (blocked if on active order) |
| PATCH | `/addresses/<id>/default/` | Mark as default |

---

## 9. Notifications — `/api/v1/notifications/`

| Method | Path | Notes |
|---|---|---|
| GET | `/my/` | Paginated, unread first, `?type=` filter |
| PATCH | `/<id>/read/` | Mark one |
| PATCH | `/read-all/` | Mark all |
| GET | `/settings/` | Public app_settings (10-min cache) |
| GET / POST | `/admin/settings/` | Admin CRUD |
| PATCH | `/admin/settings/bulk/` | Bulk update — body: `[{key, value}]` |
| POST | `/admin/send/` | Broadcast push — `{ title_ar, title_en, body_ar, body_en, type, target, branch_id?, link? }` |

---

## 10. Wallet — `/api/v1/wallet/`

| Method | Path | Notes |
|---|---|---|
| GET | `/balance/` | `{ wallet_balance, loyalty_points }` |
| GET | `/transactions/` | Paginated history |

Plus `/api/v1/auth/admin/customers/<id>/wallet/` — admin credit/debit `{ type, amount, reason }`.

---

## 11. Ratings — `/api/v1/ratings/`

| Method | Path | Notes |
|---|---|---|
| POST | `/` | `{ order_id, product_quality_rating, delivery_speed_rating, comment?, photo_url? }` |
| PATCH | `/<id>/` | Edit (owner only) |
| GET | `/preparer/<uuid>/` | Ratings for this preparer's orders |

---

## 12. Promotions & delivery fees — `/api/v1/promotions/`

| Method | Path | Notes |
|---|---|---|
| POST | `/promotions/validate/` | `{ code, store_id, subtotal, category_ids? }` → `{ valid, discount_amount, ... }` |
| Admin CRUD | `/admin/promotions/` and `/admin/delivery-fees/` | Standard list/create/detail patterns |

---

## 13. Branches — `/api/v1/branches/`

| Method | Path | Notes |
|---|---|---|
| GET | `/` | Public, filter via `?store_id=` |
| GET / POST | `/admin/` | Admin CRUD |
| PATCH | `/admin/<id>/status/` | Toggle active |

---

## 14. Reports — `/api/v1/reports/`

All accept `from_date`, `to_date`, `page`, `limit`, **`export=xlsx|pdf`**.

| Path | Columns |
|---|---|
| `sales/` | date, order_number, product, barcode, qty, unit_price, line_total, payment_method, customer, phone, address |
| `payments/` | date, order_number, amount, payment_method, driver |
| `out-of-stock/` | product, barcode, category, waitlist_count |
| `cancelled-orders/` | date, order_number, amount, reason, cancelled_by, driver |
| `preparation-time/` | date, order_number, accepted_at, prepared_at, duration_mins, preparer |
| `top-products/` | product, barcode, category, qty_sold, revenue |
| `driver-performance/` | driver, orders_completed, avg_delivery_mins, avg_rating, cash_collected |
| `inventory/` | product, barcode, opening, received, sold, adjustments, closing |
| `top-customers/` | customer, phone, order_count, total_spent, avg_order_value, points |
| `adjustments/` | order_number, original, alternative, preparer, approval_status, price_diff, action_type, date |
| `promotions/` | code, name, discount, usage_count, total_discount, is_active |
| `daily-revenue/` | date, total_sales, cash, online, pos, wallet, points_value, delivery_fees, orders |

PDF export uses `reportlab` + `arabic-reshaper` + `python-bidi` for RTL Arabic shaping.

---

## 15. Uploads — `/api/v1/uploads/`

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/presign/` | `{ filename, content_type, folder }` | Returns presigned S3 PUT URL (5-min). Client uploads directly to S3. |

---

## 16. WebSockets

| URL | Room | Events |
|---|---|---|
| `wss://.../ws/order/<order_number>/` | per-order | `order:status_changed`, `order:item_adjusted`, `driver:location` |
| `wss://.../ws/admin/` | global admin | `order:new`, `order:status_changed`, `driver:location`, `product:availability_changed` |
| `wss://.../ws/admin/store/<store_id>/` | per-store admin | Scoped to that store |
| `wss://.../ws/driver/<driver_id>/` | per-driver | `order:new`, `adjustment:response` |
| `wss://.../ws/user/<user_id>/` | per-user | `notification:new` |

---

## 17. Pagination & filtering conventions

- `?page=1&limit=20` (max 100)
- Sort: `?ordering=field` or `?ordering=-field`
- Search: `?search=`
- Filter: any field name in `filterset_fields` of the view

---

## 18. Auth & store-scoping rules (server-enforced)

| Role | `store_id` | What they see |
|---|---|---|
| customer | NULL | Cross-store; their own data only |
| preparer / driver | SET | Orders in their store assigned to them OR unassigned pool |
| admin | NULL | Super Admin — every store, every order |
| admin | SET | Store Admin — only their store |
| branch_manager | SET (+ branch_id) | Their branch within their store |
| support | SET | Read-only within their store (POST/PATCH/DELETE blocked) |

Filtering is applied **server-side** in every admin view's `get_queryset`. Clients cannot escape it by passing a `?store_id=` override.

---

## 19. Throttle limits

| Throttle | Limit |
|---|---|
| Anonymous | 100/min |
| Authenticated | 300/min |
| `POST /send-otp/` | 3/min per phone |
| `POST /verify-otp/` | 5/min per phone |
| `PATCH /location/` | 12/min (≈ 1/5s) per driver |
| `POST /login/` | 10/min per phone |
