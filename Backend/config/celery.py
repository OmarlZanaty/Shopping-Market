import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

app = Celery('shopping_market')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

app.conf.beat_schedule = {
    'expire-discounts-every-minute': {
        'task': 'apps.orders.tasks.expire_discounts',
        'schedule': 60.0,
    },
    'send-smart-notifications-daily': {
        'task': 'apps.orders.tasks.send_smart_notifications',
        'schedule': 86400.0,
    },
}
