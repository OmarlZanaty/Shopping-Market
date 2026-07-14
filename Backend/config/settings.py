"""
Shopping Market — Production Settings
Multi-store delivery platform backend.
"""
import os
from pathlib import Path
from decouple import config, Csv
from datetime import timedelta

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = config('SECRET_KEY', default='django-insecure-change-this-in-production-use-50-char-random-string')
DEBUG = config('DEBUG', default=False, cast=bool)
ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='localhost,127.0.0.1', cast=Csv())

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Third party
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'django_filters',
    'channels',
    'drf_spectacular',
    'simple_history',
    # Local apps — order matters for FK resolution
    'apps.core',
    'apps.stores',
    'apps.users',
    'apps.branches',
    'apps.products',
    'apps.promotions',
    'apps.orders',
    'apps.notifications',
    'apps.analytics',
]

# Optional work-in-progress apps. They are NOT committed to the repo, so the
# production image doesn't contain them — enabling them there crashes startup
# ("model … isn't in an application in INSTALLED_APPS"). Gate them behind a flag
# (off by default); set ENABLE_WIP_APPS=true locally where the apps exist.
ENABLE_WIP_APPS = config('ENABLE_WIP_APPS', default=False, cast=bool)
if ENABLE_WIP_APPS:
    INSTALLED_APPS += ['apps.payments', 'apps.ai']

MIDDLEWARE = [
    'apps.core.middleware.RequestIDMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.locale.LocaleMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'simple_history.middleware.HistoryRequestMiddleware',
    'apps.core.middleware.SecurityHeadersMiddleware',
]

ROOT_URLCONF = 'config.urls'
AUTH_USER_MODEL = 'users.User'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

ASGI_APPLICATION = 'config.asgi.application'
WSGI_APPLICATION = 'config.wsgi.application'

# ── Database ──────────────────────────────────────────────────────────────────
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': config('DB_NAME', default='shopping_market'),
        'USER': config('DB_USER', default='postgres'),
        'PASSWORD': config('DB_PASSWORD', default='postgres'),
        'HOST': config('DB_HOST', default='localhost'),
        'PORT': config('DB_PORT', default='5432'),
        # Spec: pool min 5 / max 20. Django's psycopg2 driver doesn't expose a
        # pool natively — use pgbouncer in front for true pooling. CONN_MAX_AGE
        # gives persistent connections within a worker.
        'CONN_MAX_AGE': 60,
        'OPTIONS': {'connect_timeout': 10},
    }
}

# ── Cache & Channels ──────────────────────────────────────────────────────────
REDIS_URL = config('REDIS_URL', default='redis://localhost:6379/0')
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': REDIS_URL,
        'KEY_PREFIX': 'sm',
        'TIMEOUT': 300,
    }
}
CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {'hosts': [REDIS_URL]},
    }
}

# ── Auth ──────────────────────────────────────────────────────────────────────
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# JWT — 2 h access (was 15 min — too short for a shopping session),
#        30 day sliding refresh, rotate + blacklist on every use.
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=2),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# ── DRF ───────────────────────────────────────────────────────────────────────
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': ['rest_framework.permissions.IsAuthenticated'],
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'DEFAULT_PAGINATION_CLASS': 'apps.core.pagination.StandardPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
    'EXCEPTION_HANDLER': 'apps.core.exceptions.exception_handler',
    'DEFAULT_THROTTLE_CLASSES': [
        'apps.core.throttling.GlobalAnonThrottle',
        'apps.core.throttling.GlobalUserThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '100/min',
        'user': '300/min',
        'otp_send': '3/min',
        'otp_verify': '5/min',
        'driver_location': '12/min',
        'staff_login': '10/min',
    },
}

# ── CORS ──────────────────────────────────────────────────────────────────────
CORS_ALLOWED_ORIGINS = config(
    'CORS_ORIGINS',
    default='http://localhost:3000,http://localhost:5173,http://localhost:8080',
    cast=Csv(),
)
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGIN_REGEXES = [r'^https://.*\.shopping-market\.com$']
CORS_ALLOW_HEADERS = [
    'accept', 'accept-encoding', 'authorization', 'content-type', 'dnt',
    'origin', 'user-agent', 'x-csrftoken', 'x-requested-with', 'x-request-id',
    'x-app-version', 'accept-language',
]

# ── i18n ──────────────────────────────────────────────────────────────────────
LANGUAGE_CODE = 'ar'
LANGUAGES = [('ar', 'Arabic'), ('en', 'English')]
TIME_ZONE = 'Africa/Cairo'
USE_I18N = True
USE_TZ = True
LOCALE_PATHS = [BASE_DIR / 'locale']

# ── Static & Media ────────────────────────────────────────────────────────────
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# ── S3 ────────────────────────────────────────────────────────────────────────
USE_S3 = config('USE_S3', default=False, cast=bool)
if USE_S3:
    AWS_ACCESS_KEY_ID = config('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = config('AWS_SECRET_ACCESS_KEY')
    AWS_STORAGE_BUCKET_NAME = config('AWS_STORAGE_BUCKET_NAME')
    AWS_S3_REGION_NAME = config('AWS_S3_REGION_NAME', default='me-south-1')
    AWS_S3_FILE_OVERWRITE = False
    AWS_DEFAULT_ACL = 'public-read'
    AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'
    AWS_S3_SIGNATURE_VERSION = 's3v4'
    AWS_QUERYSTRING_AUTH = False  # public URLs by default; presigned via boto3 explicitly
    DEFAULT_FILE_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'
    MEDIA_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ── External services ────────────────────────────────────────────────────────
# Single service-account path, used both for FCM push (apps/notifications) and
# for verifying Firebase Phone Auth ID tokens (apps/users/otp_views.py). These
# used to be two separate settings keys (FIREBASE_CREDENTIALS_PATH and
# FIREBASE_SERVICE_ACCOUNT_JSON) — only the former was ever set via .env, so
# the latter silently fell back to a relative default instead of sharing the
# real configured path.
FIREBASE_CREDENTIALS_PATH = config('FIREBASE_CREDENTIALS_PATH', default='firebase-credentials.json')

# Sign in with Apple — identity tokens are verified against Apple's JWKS and
# must have one of these bundle IDs as their `aud` claim.
APPLE_BUNDLE_IDS = config('APPLE_BUNDLE_IDS', default='com.almobarmg.shoppingmarket', cast=Csv())

# Payment Gateways
PAYMOB_API_KEY = config('PAYMOB_API_KEY', default='')
PAYMOB_INTEGRATION_ID = config('PAYMOB_INTEGRATION_ID', default='')
PAYMOB_IFRAME_ID = config('PAYMOB_IFRAME_ID', default='')
PAYMOB_HMAC_SECRET = config('PAYMOB_HMAC_SECRET', default='')
FAWRY_MERCHANT_CODE = config('FAWRY_MERCHANT_CODE', default='')
GEMINI_API_KEY = config('GEMINI_API_KEY', default='')

# OTP provider
SMS_PROVIDER = config('SMS_PROVIDER', default='log')  # 'log' | 'vonage' | 'twilio'
SMS_API_KEY = config('SMS_API_KEY', default='')
SMS_API_SECRET = config('SMS_API_SECRET', default='')
SMS_SENDER_ID = config('SMS_SENDER_ID', default='ShoppingMkt')

# Points
POINTS_PER_EGP = config('POINTS_PER_EGP', default=1, cast=int)
POINTS_VALUE_EGP = config('POINTS_VALUE_EGP', default=0.05, cast=float)
POINTS_RATING_BONUS = config('POINTS_RATING_BONUS', default=5, cast=int)

# Order timing
WEIGHT_DIFF_APPROVAL_TIMEOUT_MINS = config('WEIGHT_DIFF_APPROVAL_TIMEOUT_MINS', default=15, cast=int)
AUTO_CLOSE_TIMEOUT_HOURS = config('AUTO_CLOSE_TIMEOUT_HOURS', default=2, cast=int)

# Image processing
MAX_IMAGE_SIZE_MB = 10
IMAGE_RESIZE_MAX_WIDTH = 800
IMAGE_RESIZE_QUALITY = 85

# ── API docs ──────────────────────────────────────────────────────────────────
SPECTACULAR_SETTINGS = {
    'TITLE': 'Shopping Market API',
    'DESCRIPTION': 'Multi-store delivery platform — Customer, Agent, Admin APIs',
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
}

# ── Celery ────────────────────────────────────────────────────────────────────
CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
CELERY_TASK_TIME_LIMIT = 5 * 60
CELERY_TASK_SOFT_TIME_LIMIT = 4 * 60

from celery.schedules import crontab  # noqa: E402
CELERY_BEAT_SCHEDULE = {}
if ENABLE_WIP_APPS:
    CELERY_BEAT_SCHEDULE.update({
        'ai-recompute-recommendations': {
            'task': 'apps.ai.tasks.recompute_all_recommendations',
            'schedule': crontab(hour=2, minute=0),      # 02:00 Cairo nightly
        },
        'ai-recompute-trending': {
            'task': 'apps.ai.tasks.recompute_trending',
            'schedule': crontab(minute=0),              # every hour
        },
    })

# ── Logging (structured) ──────────────────────────────────────────────────────
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{asctime} {levelname} {name} {message}',
            'style': '{',
        },
        'json': {
            'format': '{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'json' if not DEBUG else 'verbose',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO' if not DEBUG else 'DEBUG',
    },
    'loggers': {
        'apps': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'apps.requests': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.db.backends': {
            'level': 'WARNING',  # silence SQL noise; flip to DEBUG when needed
        },
    },
}

# ── CSRF trusted origins (required for Django admin over HTTP in staging) ─────
_raw_hosts = config('ALLOWED_HOSTS', default='localhost,127.0.0.1')
CSRF_TRUSTED_ORIGINS = [
    f'http://{h}' for h in _raw_hosts.split(',') if h.strip()
] + [
    f'https://{h}' for h in _raw_hosts.split(',') if h.strip()
]

# ── Security (production only) ────────────────────────────────────────────────
# HTTPS_ENABLED must be explicitly set True in .env once SSL is in place.
_https = config('HTTPS_ENABLED', default=False, cast=bool)
if not DEBUG:
    SECURE_HSTS_SECONDS = 31536000 if _https else 0
    SECURE_HSTS_INCLUDE_SUBDOMAINS = _https
    SECURE_HSTS_PRELOAD = _https
    SECURE_SSL_REDIRECT = False
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https') if _https else None
    SESSION_COOKIE_SECURE = _https
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    CSRF_COOKIE_SECURE = _https
    CSRF_COOKIE_HTTPONLY = False  # must be readable by JS for admin login
    CSRF_COOKIE_SAMESITE = 'Lax'
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = 'strict-origin-when-cross-origin'
    X_FRAME_OPTIONS = 'DENY'

# Body size limits
DATA_UPLOAD_MAX_MEMORY_SIZE = 11 * 1024 * 1024  # 11 MB
FILE_UPLOAD_MAX_MEMORY_SIZE = 11 * 1024 * 1024
