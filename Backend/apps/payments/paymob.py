"""
Paymob Accept API client — 3-step flow:
  1. Authentication token
  2. Create Paymob order
  3. Generate payment key → return iframe URL

Docs: https://docs.paymob.com/docs/accept-standard-redirect
"""
import logging
import requests
from django.conf import settings

logger = logging.getLogger(__name__)

PAYMOB_BASE = 'https://accept.paymob.com/api'


class PaymobError(Exception):
    pass


def _auth_token() -> str:
    """Step 1 — Get short-lived auth token from Paymob."""
    resp = requests.post(
        f'{PAYMOB_BASE}/auth/tokens',
        json={'api_key': settings.PAYMOB_API_KEY},
        timeout=15,
    )
    if resp.status_code != 201:
        raise PaymobError(f'Paymob auth failed: {resp.status_code} {resp.text}')
    token = resp.json().get('token')
    if not token:
        raise PaymobError('Paymob auth returned no token')
    return token


def _create_order(auth_token: str, amount_cents: int, merchant_order_id: str) -> str:
    """Step 2 — Register the order with Paymob; returns Paymob order ID."""
    payload = {
        'auth_token': auth_token,
        'delivery_needed': 'false',
        'amount_cents': str(amount_cents),
        'currency': 'EGP',
        'merchant_order_id': merchant_order_id,
        'items': [],
    }
    resp = requests.post(
        f'{PAYMOB_BASE}/ecommerce/orders',
        json=payload,
        timeout=15,
    )
    if resp.status_code not in (200, 201):
        raise PaymobError(f'Paymob order creation failed: {resp.status_code} {resp.text}')
    order_id = resp.json().get('id')
    if not order_id:
        raise PaymobError('Paymob order creation returned no id')
    return str(order_id)


def _payment_key(
    auth_token: str,
    paymob_order_id: str,
    amount_cents: int,
    billing_data: dict,
    integration_id: int,
) -> str:
    """Step 3 — Generate payment key; returns the single-use token."""
    payload = {
        'auth_token': auth_token,
        'amount_cents': str(amount_cents),
        'expiration': 3600,
        'order_id': paymob_order_id,
        'billing_data': billing_data,
        'currency': 'EGP',
        'integration_id': integration_id,
        'lock_order_when_paid': 'false',
    }
    resp = requests.post(
        f'{PAYMOB_BASE}/acceptance/payment_keys',
        json=payload,
        timeout=15,
    )
    if resp.status_code != 201:
        raise PaymobError(f'Paymob payment key failed: {resp.status_code} {resp.text}')
    token = resp.json().get('token')
    if not token:
        raise PaymobError('Paymob payment key returned no token')
    return token


def create_payment(
    amount_egp: float,
    merchant_order_id: str,
    customer_name: str,
    customer_phone: str,
    customer_email: str = 'NA',
) -> dict:
    """
    Full 3-step Paymob flow.

    Returns:
        {
            'paymob_order_id': str,
            'payment_key': str,
            'iframe_url': str,
        }
    Raises PaymobError on any failure.
    """
    amount_cents = int(round(amount_egp * 100))

    integration_id = int(settings.PAYMOB_INTEGRATION_ID)
    iframe_id = settings.PAYMOB_IFRAME_ID  # comes from settings

    # Step 1
    auth = _auth_token()

    # Step 2
    paymob_order_id = _create_order(auth, amount_cents, merchant_order_id)

    # Step 3
    first, *rest = (customer_name or 'NA').split(' ', 1)
    last = rest[0] if rest else 'NA'
    billing = {
        'apartment': 'NA', 'email': customer_email or 'NA',
        'floor': 'NA', 'first_name': first, 'street': 'NA',
        'building': 'NA', 'phone_number': customer_phone or 'NA',
        'shipping_method': 'NA', 'postal_code': 'NA',
        'city': 'NA', 'country': 'EG', 'last_name': last, 'state': 'NA',
    }
    payment_key = _payment_key(auth, paymob_order_id, amount_cents, billing, integration_id)

    iframe_url = f'https://accept.paymob.com/api/acceptance/iframes/{iframe_id}?payment_token={payment_key}'

    logger.info('Paymob payment created: order=%s key=%s...', paymob_order_id, payment_key[:8])

    return {
        'paymob_order_id': paymob_order_id,
        'payment_key': payment_key,
        'iframe_url': iframe_url,
    }
