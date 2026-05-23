"""
DRF throttling classes per spec:
- Global: 100/min per IP
- OTP send: 3/min per phone
- OTP verify: 5/min per phone
- Driver location: 1 per 5 seconds per driver
"""
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle, SimpleRateThrottle


class GlobalAnonThrottle(AnonRateThrottle):
    rate = '100/min'


class GlobalUserThrottle(UserRateThrottle):
    rate = '300/min'


class OTPSendThrottle(SimpleRateThrottle):
    scope = 'otp_send'
    rate = '3/min'

    def get_cache_key(self, request, view):
        phone = (request.data or {}).get('phone', '') if hasattr(request, 'data') else ''
        ident = phone or self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}


class OTPVerifyThrottle(SimpleRateThrottle):
    scope = 'otp_verify'
    rate = '5/min'

    def get_cache_key(self, request, view):
        phone = (request.data or {}).get('phone', '') if hasattr(request, 'data') else ''
        ident = phone or self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}


class DriverLocationThrottle(SimpleRateThrottle):
    """1 request every 5 seconds per authenticated driver."""
    scope = 'driver_location'
    rate = '12/min'  # 12/min = once every 5 seconds

    def get_cache_key(self, request, view):
        if not request.user.is_authenticated:
            return self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': str(request.user.id)}


class StaffLoginThrottle(SimpleRateThrottle):
    scope = 'staff_login'
    rate = '10/min'

    def get_cache_key(self, request, view):
        phone = (request.data or {}).get('phone', '') if hasattr(request, 'data') else ''
        ident = phone or self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}
