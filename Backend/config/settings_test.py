"""
Test settings: production settings with the external services swapped out.

Runs the suite on an in-memory SQLite database with local-memory cache and
channel layer, so `manage.py test` needs no Postgres, no Redis and no S3:

    DJANGO_SETTINGS_MODULE=config.settings_test python manage.py test apps.products
"""
from .settings import *  # noqa: F401,F403

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

CACHES = {
    'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'},
}

CHANNEL_LAYERS = {
    'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'},
}

# Fast, deterministic password hashing — tests create a lot of users.
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']

CELERY_TASK_ALWAYS_EAGER = True
EMAIL_BACKEND = 'django.core.mail.backends.locmem.EmailBackend'
DEFAULT_FILE_STORAGE = 'django.core.files.storage.FileSystemStorage'
DEBUG = False
