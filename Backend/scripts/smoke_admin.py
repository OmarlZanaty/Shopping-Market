#!/usr/bin/env python
"""
Admin-dashboard API smoke test.

Logs in as an admin and exercises every READ endpoint the Admin Dashboard uses,
reporting any non-2xx response. This catches path mismatches (404), permission
problems (403), and server errors (500) across the whole admin surface in one
run — the contract bugs that show up as "blank page / nothing loads".

Usage (run on the server, hitting the backend directly):

    docker exec -it shoppingmarket-backend \
        python scripts/smoke_admin.py --phone <admin_phone> --password <password>

Or against nginx:

    python scripts/smoke_admin.py --base http://localhost/api/v1 --phone ... --password ...

Exits 0 if everything passed, 1 if any endpoint failed, 2 if login failed.
Only GETs are exercised — no data is modified.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

# READ endpoints the dashboard calls. {days}/page params use harmless defaults.
ENDPOINTS = [
    '/health/',
    '/analytics/dashboard/',
    '/analytics/sales/daily/?days=14',
    '/analytics/sales/categories/?days=30',
    '/analytics/sales/products/?days=30',
    '/analytics/sales/branches/?days=30',
    '/analytics/drivers/?days=30',
    '/analytics/ratings/?days=30',
    '/analytics/inventory/',
    '/analytics/points/?days=30',
    '/analytics/banners/',
    '/analytics/orders/peak-hours/?days=30',
    '/analytics/orders/substitutes/',
    '/analytics/orders/price-adjustments/?days=30',
    '/analytics/orders/close-method/?days=30',
    '/analytics/customers/churn/',
    '/orders/admin/all/?page=1&ordering=-created_at',
    '/auth/admin/users/?page=1',
    '/auth/admin/users/?role=driver',
    '/auth/admin/drivers/live/',
    '/products/admin/products/?page=1',
    '/products/admin/categories/',
    '/products/admin/banners/',
    '/products/admin/media/',
    '/branches/admin/',
    '/notifications/admin/settings/',
    '/auth/superadmin/my-permissions/',
    '/auth/superadmin/admins/',
    '/auth/superadmin/audit-log/',
]


def request(method, url, token=None, data=None):
    headers = {}
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers['Content-Type'] = 'application/json'
    if token:
        headers['Authorization'] = f'Bearer {token}'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # noqa: BLE001
        return 0, str(e).encode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default='http://localhost:8000/api/v1')
    ap.add_argument('--phone', required=True)
    ap.add_argument('--password', required=True)
    args = ap.parse_args()
    base = args.base.rstrip('/')

    status, body = request('POST', f'{base}/auth/login/',
                           data={'phone': args.phone, 'password': args.password})
    if status != 200:
        print(f'LOGIN FAILED ({status}): {body[:300]!r}')
        return 2
    payload = json.loads(body)
    token = (payload.get('data') or {}).get('access') or payload.get('access')
    if not token:
        print(f'LOGIN OK but no access token in response: {body[:300]!r}')
        return 2
    print(f'Login OK. Testing {len(ENDPOINTS)} endpoints against {base}\n')

    failures = []
    for path in ENDPOINTS:
        status, body = request('GET', f'{base}{path}', token=token)
        ok = 200 <= status < 300
        mark = 'PASS' if ok else 'FAIL'
        print(f'  [{mark}] {status:>3}  GET {path}')
        if not ok:
            failures.append((path, status, body[:200]))

    print()
    if failures:
        print(f'{len(failures)} endpoint(s) FAILED:')
        for path, status, body in failures:
            print(f'  {status}  {path}\n        {body!r}')
        return 1
    print('All endpoints passed ✅')
    return 0


if __name__ == '__main__':
    sys.exit(main())
