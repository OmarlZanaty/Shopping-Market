APP_SETTINGS_CACHE_KEY = 'core:app_settings'
APP_SETTINGS_CACHE_TTL = 600  # 10 min

CATEGORIES_CACHE_KEY = 'core:categories:store:{store_id}'
CATEGORIES_CACHE_TTL = 300  # 5 min

BANNERS_CACHE_KEY = 'core:banners:store:{store_id}'
BANNERS_CACHE_TTL = 300

STORES_LIST_CACHE_KEY = 'core:stores:list'
STORES_LIST_CACHE_TTL = 300


def categories_key(store_id):
    return CATEGORIES_CACHE_KEY.format(store_id=store_id or 'all')


def banners_key(store_id):
    return BANNERS_CACHE_KEY.format(store_id=store_id or 'all')
