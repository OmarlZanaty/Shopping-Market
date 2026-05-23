# CODE AUDIT — Shopping Market Backend

**Date:** 2026-05-21
**Auditor:** Senior backend architect (automated pass)
**Scope:** Full `/Backend` codebase against the multi-store production spec.

---

## 1. Stack reality vs. spec

| Layer | Spec calls for | What exists | Action |
|---|---|---|---|
| Runtime | Node.js / Express | Python / Django 4.2 + DRF 3.14 | **Keep Django.** ~5 MB of working code (models, views, Celery tasks, Channels consumers, admin views, audit log). Re-platforming would cost months for zero functional gain — the 3 clients (Flutter customer, Flutter agent, Next.js admin) only see HTTP/JSON. |
| Database | MySQL | PostgreSQL (psycopg2) | **Keep Postgres.** Superset of MySQL for our needs (JSONB, GIN full-text, partial indexes). The spec's MySQL-specific bits (FULLTEXT, MATCH AGAINST) translate to GIN + `tsvector`. |
| Migrations | Knex.js | Django migrations (none generated yet — only `__init__.py` in every `migrations/`) | Generate Django migrations for every model. |
| ORM/validation | express-validator + raw Knex | DRF serializers (fully parameterized, no SQL string interpolation) | **Already safer than spec.** No raw SQL exists in the codebase. |
| Real-time | ws / socket.io | Django Channels + channels-redis | **Already exists** for order tracking, admin dashboard, driver alerts (`apps/orders/consumers.py`). |
| Queue | Bull | Celery + redis | **Already exists** with beat schedule for discount expiry + smart notifications (`config/celery.py`, `apps/orders/tasks.py`). |
| Auth | JWT 15 min / refresh 30 d | SimpleJWT 7 d / 90 d with rotation + blacklist | Tighten to 15 min / 30 d. |
| File storage | S3 presigned | django-storages + boto3 (USE_S3 flag) | **Already exists.** |
| Push | FCM | firebase-admin (`apps/notifications/utils.py`) | **Already exists.** |
| API docs | Hand-written | drf-spectacular OpenAPI | **Already better than spec.** Keep + add `API_CONTRACT.md` hand-written reference. |

---

## 2. Existing models — table-by-table audit

### Table: `users.User`  (apps/users/models.py)

- PK is `UUIDField` (spec says INT). **Keeping UUID** — already referenced across orders, ratings, addresses. Migrating to INT would break every FK.
- Roles enum: `admin / driver / customer`. **Spec requires:** `customer / preparer / driver / admin / branch_manager / support`. **Action:** extend the enum.
- **Missing FK:** `store_id` (multi-store scoping). **Action:** add nullable FK; null = customer (global), set = staff.
- **Missing field:** `is_blocked`, `block_reason`, `last_seen`. **Action:** add.
- Field name mismatches (spec → existing):
  - `name` → `full_name`  (keep existing, alias in serializer)
  - `avatar_url` → `avatar` (ImageField) + `image_url_s3`  (keep)
  - `national_id_photo_url` → `id_card_image`  (rename or alias)
- `NullBooleanField` is deprecated in Django 4.x. **Not used on User**, but is used on `OrderItem.customer_approved` and `OrderAdjustment.customer_approved`. **Action:** replace with `BooleanField(null=True, blank=True)`.

### Table: `users.Address`  (apps/users/models.py)

- All required fields exist. `floor_number` / `apartment_number` allow blank — **spec requires NOT NULL.** Action: tighten validation in serializer (model can stay tolerant for legacy rows).

### Table: `branches.Branch`  (apps/branches/models.py)

- **Missing:** `store_id`, `manager_id`, `is_coastal`, `coastal_start_date`, `coastal_end_date`, `operating_hours` (JSON), per-branch sort_order.
- Has `delivery_fee` but spec wants this on a separate `delivery_fees` table with zones — **add** that table, keep this field for the default fallback fee.
- Has `opening_time`/`closing_time` — spec wants JSON `operating_hours`. **Action:** add JSON field, keep simple fields for back-compat.

### Table: `products.Category`  (apps/products/models.py)

- **Missing:** `store_id`, `parent_id` (hierarchical), `color_hex`, `is_visible` (only has `is_active`).
- `image` exists but spec wants `icon_url`. Has `icon` (emoji) too. **Action:** add `icon_url` URLField alongside.

### Table: `products.Product`

- **Missing:** `store_id`, `cost_price`, `weight_tolerance_pct`, `discount_percentage` stored field, `is_weight_based`, `low_stock_threshold` exists ✓, separate `unit_type` exists as `sell_unit` (alias).
- Branch link is single-FK (`branch`). **Spec requires** product-branches pivot with per-branch stock. **Action:** add `ProductBranch` pivot model, deprecate single FK over time.
- `quantity_in_stock` exists (spec calls it `stock_quantity` — alias in serializer).
- M2M `alternative_products` and `related_products` exist (spec wants pivot tables, but Django M2M creates pivot tables automatically — equivalent).
- `is_featured` exists (not in spec, keep).
- `simple_history.HistoricalRecords()` already tracks all changes. **Bonus:** spec didn't ask for product history but it's there.

### Table: `products.Banner`

- **Missing:** `store_id`, `branch_id` (already has `link_category`/`link_product` for navigation but no scoping).
- Has rich analytics (`view_count`, `click_count`, `purchase_count`, `ctr`). **Bonus:** spec only mentions `click_count`.
- ⚠️ **Bug in `apps/products/views.py:121`:** `BannerClickView` uses `Banner.objects.filter(pk=pk).update(click_count=Q('click_count') + 1)`. `Q('...')` is an SQL filter object, not a value — this **raises TypeError at runtime.** Must be `F('click_count') + 1`.

### Table: `products.StockWaitlist`

- All required fields exist (matches spec's `waitlist` table). Unique constraint correct.

### Table: `products.MediaLibrary`

- Not in spec. Extra functionality. **Keep.**

### Table: `orders.Order`

- **Missing:** `store_id`, `preparer_id`, `address_id` FK (currently denormalized fields), `amount_collected`, `cancellation_reason`, `cancelled_by`, `closed_by_driver_at`, `delivery_photo_url` (has `driver_proof_image` ImageField — alias).
- Status enum missing **`accepted`** stage. Currently goes `new → preparing → out_for_delivery → delivered`. **Action:** add `accepted`.
- `payment_method` values: `cash / card / wallet / points / mixed`. Spec wants `cash / online / pos / wallet / points / mixed`. **Action:** rename `card → online`, add `pos`.
- `order_id` field exists (CHAR(30), spec format `ORD-YYYYMMDD-###` ✓).
- ⚠️ **Race condition in `generate_order_id()` (models.py:8):** `Order.objects.filter(created_at__date=...).count() + 1` is not atomic — under concurrent load this can produce duplicate `order_id` values. Spec test #15 (100 concurrent orders) will fail. **Action:** use a database sequence per day (Postgres `nextval`) or wrap in `SELECT FOR UPDATE`.

### Table: `orders.OrderItem`

- Status enum missing several spec values: `picked`, `weight_adjusted`, `price_adjusted`, `added`, `removed`. Has `pending / collected / substitute / rejected / unavailable`. **Action:** extend choices to match spec.
- **Missing:** `weight_ordered`, `weight_actual`, `weight_difference_approved`, `final_price`, `line_total` (currently computed property — should be persisted for reporting).
- Has `weight_variance` and `weight_variance_amount` — partial spec compliance.
- ⚠️ `customer_approved = models.NullBooleanField(...)` — deprecated.

### Table: `orders.OrderAdjustment`

- Action types: `price_change / quantity_change / substitute / item_added / item_removed`. **Spec wants 13 types** (incl. `barcode_scanned`, `photo_taken`, `data_shared`, `weight_diff_sent`, etc.). **Action:** extend the enum.
- **Missing:** `customer_approval_status` (ENUM: pending/approved/rejected). Has `customer_approved` (Bool|null) — close enough but the spec's tri-state ENUM is cleaner. **Action:** add field, keep both for transition.

### Table: `orders.OrderRating`

- Has `product_rating + delivery_rating + comment + photo` ✓. Plus `sentiment` (bonus). **Spec wants** field renames: `product_quality_rating`, `delivery_speed_rating`. Serializer aliases handle this.

### Table: `orders.SmartTimerAutoClose`

- Exists, supports the 2-hour auto-close flow. ✓

### Tables — MISSING ENTIRELY

| Spec table | Status | Action |
|---|---|---|
| `stores` | Not exists | **Create** — root of multi-store architecture. |
| `promotions` | Not exists | **Create.** |
| `delivery_fees` (zones) | Not exists; single fee on `Branch` | **Create.** |
| `wallet_transactions` | Not exists (only `PointsTransaction`) | **Create**, mirroring PointsTransaction shape. |
| `product_branches` pivot | Not exists; single FK on Product | **Create.** |
| `refresh_tokens` | SimpleJWT blacklist used instead | **Keep SimpleJWT.** Equivalent. |
| `notifications` (InAppNotification has it) | Exists but missing `type` enum and `read_at` | **Extend.** |

### Tables — existing extras (not in spec, keep)

- `users.PointsTransaction` — loyalty ledger
- `users.DataShareLog` — driver sharing customer data audit (privacy compliance)
- `users.AdminProfile` + `users.AdminAuditLog` + `AdminPermission` enum — **excellent** existing RBAC with granular permission JSON, preset roles, audit log. Spec's simple `admin / branch_manager / support` is a subset of this. **Keep both** — map spec roles to AdminProfile presets.
- `products.MediaLibrary` — reusable image library
- `notifications.AppSettings` — key/value store ✓

---

## 3. Existing endpoints — coverage map

Format: ✓ exists | + extend | × missing

### Auth (`/api/v1/auth/`)
- ✓ `POST /register/`, `POST /login/`, `POST /social-login/`, `POST /biometric/register/`, `POST /biometric/login/`, `POST /logout/`, `POST /token/refresh/`
- ✓ `GET/PATCH /profile/`, `POST /fcm-token/`, `POST /location/`, `POST /online-toggle/`
- × `POST /send-otp/` (spec requires OTP login — 3/min rate limit)
- × `POST /verify-otp/`
- ✓ Addresses CRUD, points history, data-share-log
- ✓ Admin user CRUD, super-admin RBAC suite (rich existing implementation)

### Products (`/api/v1/products/`)
- ✓ Customer: list, detail, barcode, search/suggestions, categories, banners + click, waitlist toggle
- ✓ Admin: products CRUD, bulk price, toggle availability, categories CRUD, banners CRUD, media library
- × `POST /products/bulk` (action/payload-driven)
- × `POST /products/import` (Excel/CSV upload)
- × `GET /products/:id/waitlist` (who's waiting)
- × `POST /products/:id/notify-waitlist` (manual blast)
- × Category drag-drop reorder
- × Stores endpoints (entire group)

### Orders (`/api/v1/orders/`)
- ✓ Customer: list, create, detail, confirm-receipt, rate, approve adjustment
- ✓ Driver: list, accept, start-delivery, mark-delivered, auto-close, adjust-price, substitute, add-item
- ✓ Admin: list, detail, assign-driver
- × **Preparer flow entirely missing:** accept/reject (separate from driver), start-preparing, ready (preparer-done-awaiting-driver), picked-up (driver-pickup from preparer)
- × Item-level: qty adjust, mark-unavailable, weight submission, delete item endpoint
- × `force-close` driver endpoint (auto-close exists but needs photo + reason)
- × Customer add/remove items on in-progress order
- × Admin assign-preparer, admin cancel-with-reason, admin process-return, admin /live counts

### Agent inventory & logging
- × `GET /agent/inventory/scan/:barcode`
- × `PATCH /agent/inventory/mark-available/:productId`
- × `POST/GET /agent/orders/:id/log`
- × `POST /agent/orders/:id/share`

### Admin reports (`/api/v1/analytics/`)
- ✓ Dashboard summary, sales-by-day, sales-by-products, sales-by-categories, sales-by-branches, driver-performance, close-method, price-adjustments, substitutes, ratings, inventory, points, banners, churn, peak-hours
- × Full spec requires **12 named reports with Excel + PDF export with RTL Arabic.** Existing reports return JSON only.

### Branches (`/api/v1/branches/`)
- ✓ Public list, admin CRUD
- × Toggle active, manager assignment, operating-hours config

### Notifications
- ✓ Settings public + admin CRUD, my-notifications, mark-read single, admin broadcast
- × `PATCH /read-all`, type filter

### Stores — ENTIRELY MISSING
- × `GET /api/stores/`, `GET /api/stores/config`, `GET /api/stores/:id`
- × Admin store CRUD, multistore toggle, default_store_id

---

## 4. Security audit

| Area | Status | Finding |
|---|---|---|
| SQL injection | ✅ **Safe** | No raw SQL in codebase. DRF + Django ORM = parameterized everywhere. |
| Helmet equiv. | ⚠️ Partial | `SecurityMiddleware` enabled. SSL redirect, HSTS, cookie-secure flags only in `if not DEBUG` — **good for prod**. Missing CSP, X-Content-Type-Options. |
| CORS | ⚠️ Permissive | `CORS_ALLOW_CREDENTIALS = True` with whitelist from env. Whitelist works; **harden by disabling wildcards.** |
| Rate limiting | ❌ **Absent** | No `django-ratelimit` or `django-axes` installed. **OTP brute-force is open.** Spec requires 3/min on `/send-otp` and 100/min global. |
| Password hash | ✅ | Django default = PBKDF2 (310K iterations as of 4.2). Stronger than spec's bcrypt rounds=12. |
| JWT lifetimes | ⚠️ | Access = 7 days (spec: 15 min). Refresh = 90 days (spec: 30 days). **Tighten.** |
| Refresh rotation | ✅ | `ROTATE_REFRESH_TOKENS=True`, `BLACKLIST_AFTER_ROTATION=True`. |
| File upload validation | ❌ | `ImageField` only checks Pillow-decodability. **No MIME allowlist, no size cap, no path-traversal scrub.** Spec wants 10 MB cap + image/jpeg|png|webp only. |
| Input validation | ✅ Mostly | DRF serializers cover most routes. `AdminBulkPriceUpdateView` accepts raw `request.data['updates']` without a serializer. **Tighten.** |
| Error sanitization | ⚠️ | `DEBUG=False` triggers stack-trace suppression. ✅. But no centralized error middleware to format `{success, data, message, errors}`. |
| Sensitive logging | ⚠️ | `apps/notifications/utils.py:45` logs phone numbers in INFO. Should be DEBUG. National ID image path could leak if logged on error. |
| Banner click bug | 🐛 | `apps/products/views.py:121` — `Q('click_count') + 1` is a runtime error. Replace with `F('click_count') + 1`. |
| `generate_order_id` race | 🐛 | `apps/orders/models.py:8` — count+1 not atomic. Concurrent orders can collide. |
| `NullBooleanField` | ⚠️ | Deprecated in Django 4.0+, removed in 5.0. Two usages in `orders/models.py`. Replace with `BooleanField(null=True)`. |

---

## 5. Performance audit

| Area | Status | Finding |
|---|---|---|
| Pagination | ⚠️ | DRF `PAGE_SIZE=20` is global default but several views (e.g. `AdminProductListView`) don't enforce pagination class. Spec requires `{ data, pagination: {page, limit, total, totalPages} }` envelope — current DRF default is `{ count, next, previous, results }`. Standardize. |
| Full-text search | ⚠️ | `SearchSuggestionsView` uses `istartswith` — no index. For 10k+ products this is a sequential scan. **Add Postgres GIN tsvector index.** |
| N+1 in serializers | ⚠️ | `ProductSerializer.get_alternatives` and `get_related` issue queries inside loops over a list. Use `prefetch_related` once in view's `get_queryset`. |
| Eager loading | ⚠️ Partial | `AdminProductListView` calls `.prefetch_related('categories', 'images')` ✓, but `AdminOrderListView.get_queryset` only `select_related`s, missing items prefetch. |
| Cache | ❌ | Redis is configured (`CACHES`) but **no view uses it.** Categories, banners, app_settings are hit on every request. |
| DB pool | ⚠️ | `CONN_MAX_AGE=60` ✓. No explicit min/max — uses Django's default persistent-connection behavior. |
| Image proxy | ✅ | S3 direct URLs when `USE_S3=True`. ✓ |
| Bulk imports | ❌ | No `POST /products/import` Excel endpoint. Celery available; would queue easily. |

---

## 6. Critical bugs to fix immediately

1. **`apps/products/views.py:121`** — `Banner.objects.filter(pk=pk).update(click_count=Q('click_count') + 1)` raises `TypeError`. Change to `F('click_count') + 1`.
2. **`apps/orders/models.py:8`** — `generate_order_id()` race condition. Wrap in transaction with row lock OR use a dedicated sequence.
3. **`apps/orders/models.py:196,237`** — `NullBooleanField` is deprecated. Replace with `BooleanField(null=True, blank=True)`.
4. **`apps/orders/views.py:425-431`** — `AdminOrderDetailView.get_object()` calls `.get(order_id=...)` without try/except; raises 500 on missing. Wrap.
5. **`apps/orders/views.py:456`** — `except (Order.DoesNotExist, Exception)` catches the broad `Exception` and returns 404 — masks real errors as "not found". Split.
6. **`apps/users/serializers.py:62`** — Egyptian phone validation accepts anything ≥ 7 digits. Spec requires exactly 11 digits starting with `01[0125]`.
7. **No `migrations/0001_initial.py` anywhere.** Database is undefined. Must generate.

---

## 7. Architectural gaps vs. spec

1. **Multi-store scoping is the biggest gap.** Currently single-tenant. Adding store_id to 8 tables + a Store model + admin scoping middleware + multistore feature flag is the largest change.
2. **Preparer role doesn't exist** — only driver picks/delivers. Spec separates preparer (picks items, scans, adjusts) from driver (transports). Need new role, new endpoints, new assignment flow.
3. **Order lifecycle stage `accepted`** is missing between `new` and `preparing`.
4. **No 15-minute approval timeout** — spec wants a Celery task that fires "call customer" after 15 min of unanswered weight/substitute/price adjustment.
5. **OTP authentication path missing** — only password and biometric exist.
6. **No `multistore_enabled` feature flag** — customer app currently has no way to know whether to show store selector.

---

## 8. Implementation strategy (next sections deliver this)

| Order | Section | Files touched |
|---|---|---|
| 1 | New `stores` app: model + migrations + admin | `apps/stores/*` |
| 2 | Add `store_id` to: User, Branch, Category, Product, Banner, Order, Promotion, DeliveryFee | each model + new migrations |
| 3 | Extend User.role enum + add `is_blocked`/`block_reason`/`last_seen` | `apps/users/models.py` |
| 4 | Add Order.preparer FK, `accepted` status, `amount_collected`, etc. | `apps/orders/models.py` |
| 5 | New models: Promotion, DeliveryFee, WalletTransaction, ProductBranch | new files |
| 6 | New permission classes: `IsSuperAdmin`, `IsStoreAdmin`, `IsBranchManager`, `IsAgent`, `IsSupportRead`. Store-scoping mixin. | `apps/users/permissions.py` |
| 7 | OTP: send/verify endpoints, throttle via `django-ratelimit` or DRF throttling | `apps/users/views.py` |
| 8 | Stores customer endpoints + config endpoint | `apps/stores/views.py` |
| 9 | Preparer endpoint suite under `/api/v1/agent/` | new `apps/orders/agent_views.py` |
| 10 | Admin stores + multistore-toggle endpoints | `apps/stores/admin_views.py` |
| 11 | 12 named reports + Excel/PDF export helpers | `apps/analytics/reports/` |
| 12 | Real-time event emitters wired into model `save()` hooks + Celery 15-min timer task | existing `tasks.py` + new |
| 13 | Security hardening: rate limit, file upload validator, response envelope middleware | `apps/core/` |
| 14 | `.env.example`, `API_CONTRACT.md`, `BACKEND_TEST_REPORT.md` | repo root |

End of audit. Proceeding to implementation.
