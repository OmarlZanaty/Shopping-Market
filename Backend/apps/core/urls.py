from django.urls import path
from django.db import connection
from django.http import JsonResponse
from .storage import S3PresignView


def health(request):
    """Liveness/readiness probe for the Docker healthcheck and uptime monitoring.

    Returns 200 only when the DB is reachable, so a wedged worker or a dead DB
    connection is detectable instead of silently 502-ing later.
    """
    try:
        with connection.cursor() as cur:
            cur.execute('SELECT 1')
        db_ok = True
    except Exception:
        db_ok = False
    return JsonResponse(
        {'status': 'ok' if db_ok else 'degraded', 'db': db_ok},
        status=200 if db_ok else 503,
    )


urlpatterns = [
    path('health/', health, name='health'),
    path('uploads/presign/', S3PresignView.as_view(), name='s3-presign'),
]
