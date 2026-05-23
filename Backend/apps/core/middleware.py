"""
Cross-cutting middleware.
"""
import logging
import time
import uuid

logger = logging.getLogger('apps.requests')


class RequestIDMiddleware:
    """Attach a unique request_id to every request for log correlation."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.request_id = request.headers.get('X-Request-ID') or uuid.uuid4().hex[:16]
        start = time.time()
        response = self.get_response(request)
        elapsed_ms = int((time.time() - start) * 1000)
        response['X-Request-ID'] = request.request_id
        try:
            user_id = getattr(request.user, 'id', None)
        except Exception:
            user_id = None
        logger.info(
            'request',
            extra={
                'request_id': request.request_id,
                'method': request.method,
                'path': request.path,
                'status': response.status_code,
                'elapsed_ms': elapsed_ms,
                'user_id': str(user_id) if user_id else None,
            },
        )
        return response


class SecurityHeadersMiddleware:
    """Tighten default security headers (helmet-equivalent)."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response.setdefault('X-Content-Type-Options', 'nosniff')
        response.setdefault('X-Frame-Options', 'DENY')
        response.setdefault('Referrer-Policy', 'strict-origin-when-cross-origin')
        response.setdefault('Permissions-Policy', 'geolocation=(self), microphone=(), camera=()')
        # Only set CSP for non-API HTML responses (admin/swagger). Don't break JSON clients.
        if response.get('Content-Type', '').startswith('text/html'):
            response.setdefault(
                'Content-Security-Policy',
                "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; "
                "script-src 'self' 'unsafe-inline'; frame-ancestors 'none'"
            )
        return response
