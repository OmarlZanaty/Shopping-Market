"""
"Do we deliver here?" — the single answer both the customer app and checkout use.

Rules, in order:
1. Branch has active zones  -> covered iff the point falls in one of them.
2. Branch has no zones      -> fall back to delivery_radius_km, exactly as
                               before this feature existed. Deploying zones
                               therefore changes nothing until someone draws one.

A store is covered if any of its active branches covers the point.
"""
from .geo import haversine_km
from .models import Branch

# Shown to the customer when nothing covers them. Deliberately warm: being told
# "you are outside the area" is a small disappointment, not an error.
OUT_OF_ZONE_AR = (
    'عذراً، لا نوصّل إلى هذا العنوان حالياً. '
    'نعمل على توسيع مناطق التوصيل قريباً 🙏'
)
OUT_OF_ZONE_EN = (
    "Sorry, we don't deliver to this address yet. "
    'We are expanding our delivery areas soon.'
)


def branch_covers(branch, lat, lng):
    """Does this branch deliver to (lat, lng)?"""
    zones = [z for z in branch.delivery_zones.all() if z.is_active]
    if zones:
        return any(zone.contains(lat, lng) for zone in zones)
    if branch.latitude is None or branch.longitude is None:
        return False
    distance = haversine_km(branch.latitude, branch.longitude, lat, lng)
    return distance <= float(branch.delivery_radius_km or 0)


def covering_branch(lat, lng, store_id=None):
    """The branch that should serve this point, or None.

    When several cover it, the nearest one wins — the same behaviour customers
    already get from the nearest-branch logic in the store serializer.
    """
    if lat is None or lng is None:
        return None

    branches = Branch.objects.filter(is_active=True).prefetch_related('delivery_zones')
    if store_id is not None:
        branches = branches.filter(store_id=store_id)

    covering = [b for b in branches if branch_covers(b, lat, lng)]
    if not covering:
        return None
    return min(
        covering,
        key=lambda b: haversine_km(b.latitude, b.longitude, lat, lng),
    )


def is_covered(lat, lng, store_id=None):
    return covering_branch(lat, lng, store_id) is not None
