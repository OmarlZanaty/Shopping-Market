"""
Central loyalty-points engine. All earn/redeem math lives here so the customer
app, admin dashboard and order pipeline share one source of truth.

Everything is driven by admin-editable AppSettings keys (see
notifications.AppSettings), so the rules can be tuned live from the dashboard
without a deploy:

    loyalty_enabled            "1"/"0"  master on/off switch
    loyalty_earn_points        points granted per earn block          (e.g. 1)
    loyalty_earn_per_egp       size of an earn block, in EGP          (e.g. 10)
        -> earn = floor(order_total / earn_per_egp) * earn_points
    loyalty_redeem_points      points needed for one redeem block     (e.g. 100)
    loyalty_redeem_egp         EGP discount granted per redeem block  (e.g. 5)
        -> egp_per_point = redeem_egp / redeem_points
    loyalty_min_redeem         min points a customer may redeem at once
    loyalty_max_redeem_percent cap on discount as % of the subtotal   (e.g. 50)

Legacy fallbacks (older installs only had these two flat rates):
    loyalty_earn_rate    points per EGP        -> earn_points/earn_per_egp
    loyalty_redeem_rate  EGP per single point  -> redeem_egp/redeem_points
"""
from decimal import Decimal, ROUND_DOWN


def _get(key, default):
    from apps.notifications.models import AppSettings
    val = AppSettings.get(key, None)
    return default if val in (None, '') else val


def _dec(key, default):
    try:
        return Decimal(str(_get(key, default)))
    except Exception:
        return Decimal(str(default))


def _int(key, default):
    try:
        return int(Decimal(str(_get(key, default))))
    except Exception:
        return int(default)


def is_enabled() -> bool:
    return str(_get('loyalty_enabled', '1')).strip() not in ('0', 'false', 'False', '')


def egp_per_point() -> Decimal:
    """Monetary value of a single point (EGP)."""
    redeem_points = _dec('loyalty_redeem_points', 0)
    redeem_egp = _dec('loyalty_redeem_egp', 0)
    if redeem_points > 0 and redeem_egp > 0:
        return redeem_egp / redeem_points
    # Legacy flat rate (EGP per point), default 0.05.
    return _dec('loyalty_redeem_rate', '0.05')


def points_for_amount(amount) -> int:
    """Points earned for spending `amount` EGP."""
    if not is_enabled():
        return 0
    amount = Decimal(str(amount or 0))
    if amount <= 0:
        return 0
    earn_points = _dec('loyalty_earn_points', 0)
    earn_per_egp = _dec('loyalty_earn_per_egp', 0)
    if earn_points > 0 and earn_per_egp > 0:
        blocks = (amount / earn_per_egp).to_integral_value(rounding=ROUND_DOWN)
        return int(blocks * earn_points)
    # Legacy flat rate (points per EGP), default 1.
    rate = _dec('loyalty_earn_rate', 1)
    return int((amount * rate).to_integral_value(rounding=ROUND_DOWN))


def clamp_redeemable_points(points_used: int, subtotal) -> int:
    """Clamp a redemption request to the configured min / max-percent rules.

    Returns the number of points actually allowed (0 if below the minimum or
    loyalty is disabled).
    """
    if not is_enabled() or points_used <= 0:
        return 0
    min_redeem = _int('loyalty_min_redeem', 0)
    if points_used < min_redeem:
        return 0
    max_pct = _dec('loyalty_max_redeem_percent', 100)
    per_point = egp_per_point()
    if per_point <= 0:
        return 0
    if 0 < max_pct < 100:
        max_discount = (Decimal(str(subtotal or 0)) * max_pct / 100)
        max_points = int((max_discount / per_point).to_integral_value(rounding=ROUND_DOWN))
        points_used = min(points_used, max_points)
    return max(points_used, 0)


def value_for_points(points_used: int) -> Decimal:
    """EGP discount for redeeming `points_used` points (2dp)."""
    if points_used <= 0:
        return Decimal('0')
    value = Decimal(points_used) * egp_per_point()
    return value.quantize(Decimal('0.01'), rounding=ROUND_DOWN)


def public_config() -> dict:
    """Serializable snapshot for the customer app / dashboard display."""
    return {
        'enabled': is_enabled(),
        'earn_points': _int('loyalty_earn_points', 1),
        'earn_per_egp': float(_dec('loyalty_earn_per_egp', 1)),
        'redeem_points': _int('loyalty_redeem_points', 20),
        'redeem_egp': float(_dec('loyalty_redeem_egp', 1)),
        'egp_per_point': float(egp_per_point()),
        'min_redeem': _int('loyalty_min_redeem', 0),
        'max_redeem_percent': float(_dec('loyalty_max_redeem_percent', 100)),
    }
