"""Verifies Sign in with Apple identity tokens server-side.

Apple issues a JWT ("identityToken") signed with one of a small set of RSA
keys published at https://appleid.apple.com/auth/keys. We fetch that JWKS
(cached to avoid hitting Apple on every login), pick the key matching the
token's `kid` header, and verify signature + issuer + audience + expiry
before trusting the token's `sub` (Apple's stable per-app user id) and
`email` claims. This mirrors how the client-trusted Google flow SHOULD work
but doesn't currently — Apple's identity must not be spoofable since it's
also used to satisfy App Store Guideline 4.8.
"""
import jwt
import requests
from django.conf import settings
from django.core.cache import cache

APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'
APPLE_ISSUER = 'https://appleid.apple.com'
_CACHE_KEY = 'apple_auth_jwks_v1'
_CACHE_TTL = 60 * 60 * 12  # 12h — Apple rotates keys infrequently


class AppleTokenError(Exception):
    pass


def _fetch_jwks():
    keys = cache.get(_CACHE_KEY)
    if keys:
        return keys
    resp = requests.get(APPLE_KEYS_URL, timeout=10)
    resp.raise_for_status()
    keys = resp.json()['keys']
    cache.set(_CACHE_KEY, keys, _CACHE_TTL)
    return keys


def verify_apple_identity_token(identity_token: str) -> dict:
    """Returns the verified claims dict (contains at least `sub`, optionally
    `email`). Raises AppleTokenError if the token is missing, malformed,
    expired, or fails signature/issuer/audience verification."""
    if not identity_token:
        raise AppleTokenError('Missing Apple identity token')

    try:
        header = jwt.get_unverified_header(identity_token)
    except jwt.exceptions.DecodeError as e:
        raise AppleTokenError(f'Malformed identity token: {e}')

    kid = header.get('kid')
    keys = _fetch_jwks()
    jwk = next((k for k in keys if k.get('kid') == kid), None)
    if jwk is None:
        # Key set may have rotated — refetch once, bypassing the cache.
        cache.delete(_CACHE_KEY)
        keys = _fetch_jwks()
        jwk = next((k for k in keys if k.get('kid') == kid), None)
    if jwk is None:
        raise AppleTokenError('No matching Apple signing key found')

    public_key = jwt.algorithms.RSAAlgorithm.from_jwk(jwk)
    audiences = list(settings.APPLE_BUNDLE_IDS)

    try:
        claims = jwt.decode(
            identity_token,
            key=public_key,
            algorithms=['RS256'],
            audience=audiences,
            issuer=APPLE_ISSUER,
        )
    except jwt.exceptions.InvalidTokenError as e:
        raise AppleTokenError(f'Invalid Apple identity token: {e}')

    if not claims.get('sub'):
        raise AppleTokenError('Apple identity token missing subject claim')
    return claims
