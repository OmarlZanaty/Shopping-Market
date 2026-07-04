"""
Celery tasks for nightly AI recomputation.

Schedule (add to CELERY_BEAT_SCHEDULE in settings):
    'ai-recompute-recommendations': {
        'task': 'apps.ai.tasks.recompute_all_recommendations',
        'schedule': crontab(hour=2, minute=0),   # 02:00 Cairo every night
    },
    'ai-recompute-trending': {
        'task': 'apps.ai.tasks.recompute_trending',
        'schedule': crontab(minute=0),            # every hour
    },
"""
import logging
from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(name='apps.ai.tasks.recompute_all_recommendations', bind=True,
             max_retries=2, default_retry_delay=120)
def recompute_all_recommendations(self):
    """
    Nightly task: recompute recommendations for every customer who placed at
    least one order. Runs in batches of 200 to avoid memory pressure.
    """
    from django.conf import settings
    from django.apps import apps
    from .engine import compute_recommendations_for_user

    User = apps.get_model(settings.AUTH_USER_MODEL)
    customers = list(
        User.objects.filter(
            role='customer',
            customer_orders__isnull=False,
        ).distinct().values_list('id', flat=True)[:5000]   # safety cap
    )
    logger.info('[AI] Recomputing recommendations for %d users', len(customers))
    ok = 0
    for uid in customers:
        try:
            u = User.objects.get(pk=uid)
            compute_recommendations_for_user(u)
            ok += 1
        except Exception as exc:
            logger.warning('[AI] Failed for user %s: %s', uid, exc)
    logger.info('[AI] Done: %d/%d users processed', ok, len(customers))
    return ok


@shared_task(name='apps.ai.tasks.recompute_trending', bind=True,
             max_retries=2, default_retry_delay=60)
def recompute_trending(self):
    """Hourly task: recompute trending products per store."""
    from .engine import compute_trending
    return compute_trending()
