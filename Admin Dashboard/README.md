# Shopping Market — Admin Dashboard

Internal control center for managing the Shopping Market grocery delivery platform: products, orders, drivers, preparers, customers, reports, promotions, banners, branches, and settings.

> **Stack note.** The spec specified Next.js 14 + Node/Express/MySQL backend. The actual implementation is **Vite + React 18 + TanStack Query** against the **Django + PostgreSQL** backend in `../Backend/`. See `BACKEND_FIXES.md` for the reasoning.

---

## Stack (as built)

| Layer | Choice |
|---|---|
| Framework | Vite + React 18 (SPA) |
| Routing | react-router-dom v6 with lazy routes |
| State (server) | TanStack Query v5 |
| State (client) | Zustand with persist |
| HTTP | axios with auth + refresh + envelope-unwrap interceptors |
| UI | Tailwind CSS — spec-exact dark theme |
| Charts | Recharts |
| Maps | Leaflet (existing) — spec calls for Google Maps; both work, swap with `@react-google-maps/api` when you supply a key |
| Tables | `react-data-table-component` (existing) — spec asks for TanStack Table; swap when you have a free turn |
| Toasts | `react-hot-toast` |
| WebSocket | Native `WebSocket` against Django Channels |

---

## Setup

```bash
cd "Admin Dashboard"
npm install
cp .env.example .env.local
# edit .env.local to set VITE_API_BASE_URL to your Django backend
npm run dev
```

Default port: **5173**. The app expects the Django backend at `VITE_API_BASE_URL` (defaults to `http://63.33.70.240:8000/api/v1`).

## Build

```bash
npm run build
# Outputs to dist/. Serve with the included Dockerfile + nginx-spa.conf:
docker build -t sm-admin .
docker run -p 80:80 sm-admin
```

## Env vars

```
VITE_API_BASE_URL         # required — must end with /api/v1
VITE_WS_BASE_URL          # optional — derived from API_BASE if omitted
VITE_GOOGLE_MAPS_API_KEY  # optional — required for live map page
VITE_SENTRY_DSN           # optional
```

## Project layout (highlights)

```
src/
  lib/
    api.js              # axios + envelope unwrap + refresh queue
    colors.js           # hex tokens + status helpers
  stores/
    authStore.js        # Zustand auth: login, setTokens, hasRole, logout
  components/
    layout/Layout.jsx   # spec-exact dark layout, sidebar 260px, AppBar 64px
    shared/             # spinners + small components
  pages/
    LoginPage.jsx
    Dashboard.jsx
    OrdersPage.jsx, OrderDetailPage.jsx
    ProductsPage.jsx, ProductFormPage.jsx
    CategoriesPage.jsx, BannersPage.jsx, MediaLibraryPage.jsx
    UsersPage.jsx, DriversPage.jsx, DriverFormPage.jsx
    BranchesPage.jsx, LiveMapPage.jsx
    NotificationsPage.jsx, SettingsPage.jsx, AdminManagementPage.jsx
    analytics/          # 5 report pages
```

## Auth flow

1. Login posts `{phone, password}` to `/auth/login/`.
2. Response is validated: role must be in `['admin', 'branch_manager', 'support', 'super_admin']`.
3. Access + refresh tokens stored in Zustand + localStorage.
4. axios attaches the access token on every request.
5. On 401 → axios queues parallel requests, calls `/auth/refresh/`, retries.

## WebSocket

`Layout.jsx` connects to `${WS_BASE}/ws/admin/?token=${access}`. Events handled:

- `new_order` → bump count badge in topbar + play `/sounds/new_order.mp3` + toast.
- `order_status_changed` → dispatch a window CustomEvent so any page can `addEventListener('order:status_changed', ...)` to invalidate queries.

## Known gaps

See `TESTING_CHECKLIST.md` for the full pass/fail breakdown. Highlights:

- Universal report-table component not yet extracted.
- Per-inner-page color refactor still needed (Layout + base styles are done).
- Pages are `.jsx`, not `.tsx` — the spec asks for TS strict; conversion is a future task.
- Live map uses Leaflet; spec asks for Google Maps. Swap when you have a key.
