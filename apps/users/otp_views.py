"""
OTP send + verify endpoints.

- send-otp: 3 / minute per phone (spec).
- verify-otp: 5 / minute per phone.
- Codes hashed before storage (SHA-256). Plaintext code goes to SMS only.
- 6-digit numeric. 5-min expiry. Max 5 attempts per code.
- DEV mode: if DEBUG=True, the code is also returned in the JSON response so
  the Flutter dev environment can complete the flow without SMS.
"""
import hashlib
import secrets
import logging

from datetime import timedelta
from django.conf import settings
from django.utils import timezone
from rest_framework import permissions, serializers, status
from rest_framework.views import APIView

from .models import User, OTPCode
from .serializers import get_tokens_for_user
from apps.core.responses import ok, fail
from apps.core.throttling import OTPSendThrottle, OTPVerifyThrottle
from apps.core.validators import validate_egyptian_phone

logger = logging.getLogger(__name__)

OTP_LENGTH = 6
OTP_TTL_MINUTES = 5
OTP_MAX_ATTEMPTS = 5


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.encode('utf-8')).hexdigest()


def _send_sms(phone: str, code: str) -> None:
    """
    Placeholder for SMS provider. Wire to Vonage / Twilio / Misr Telegraph here.
    Logs only — never log the code itself in production.
    """
    if settings.DEBUG:
        logger.info('OTP %s -> %s (DEV ONLY)', code, phone)
    else:
        logger.info('OTP sent to %s', phone)
    # Replace with provider client call. Always idempotent — provider may rate-limit too.


class SendOTPSerializer(serializers.Serializer):
    phone = serializers.CharField()

    def validate_phone(self, value):
        return validate_egyptian_phone(value)


class VerifyOTPSerializer(serializers.Serializer):
    phone = serializers.CharField()
    code = serializers.CharField(min_length=4, max_length=10)
    full_name = serializers.CharField(required=False, allow_blank=True)
    fcm_token = serializers.CharField(required=False, allow_blank=True)

    def validate_phone(self, value):
        return validate_egyptian_phone(value)

    def validate_code(self, value):
        if not value.isdigit():
            raise serializers.ValidationError('Code must be digits only')
        return value


class SendOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [OTPSendThrottle]

    def post(self, request):
        ser = SendOTPSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        phone = ser.validated_data['phone']

        # Invalidate any unused codes for this phone (one active code policy)
        OTPCode.objects.filter(phone=phone, is_used=False).update(is_used=True)

        code = ''.join(str(secrets.randbelow(10)) for _ in range(OTP_LENGTH))
        expires = timezone.now() + timedelta(minutes=OTP_TTL_MINUTES)
        OTPCode.objects.create(
            phone=phone,
            code_hash=_hash_code(code),
            expires_at=expires,
        )
        _send_sms(phone, code)

        payload = {'sent': True, 'expires_in_seconds': OTP_TTL_MINUTES * 60}
        if settings.DEBUG:
            # Surface to dev only — never in production.
            payload['debug_code'] = code
        return ok(payload, message='OTP sent successfully')


class VerifyOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [OTPVerifyThrottle]

    def post(self, request):
        ser = VerifyOTPSerializer(data=request.data)
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)

        phone = ser.validated_data['phone']
        code = ser.validated_data['code']
        full_name = ser.validated_data.get('full_name', '')
        fcm_token = ser.validated_data.get('fcm_token', '')

        otp = (
            OTPCode.objects
            .filter(phone=phone, is_used=False, expires_at__gt=timezone.now())
            .order_by('-created_at')
            .first()
        )
        if not otp:
            return fail('No active OTP. Request a new code.', status_code=400)

        if otp.attempts >= OTP_MAX_ATTEMPTS:
            otp.is_used = True
            otp.save(update_fields=['is_used'])
            return fail('Too many attempts. Request a new code.', status_code=429)

        if otp.code_hash != _hash_code(code):
            otp.attempts += 1
            otp.save(update_fields=['attempts'])
            return fail('Invalid code', status_code=400)

        # Valid — burn it.
        otp.is_used = True
        otp.save(update_fields=['is_used'])

        user, created = User.objects.get_or_create(
            phone=phone,
            defaults={
                'full_name': full_name or 'New User',
                'role': User.Role.CUSTOMER,
                'login_type': User.LoginType.OTP,
            },
        )
        if user.is_blocked:
            return fail('Account blocked', errors=[{'reason': user.block_reason}], status_code=403)
        if not user.is_active:
            return fail('Account inactive', status_code=403)
        if full_name and (not user.full_name or user.full_name == 'New User'):
            user.full_name = full_name
            user.save(update_fields=['full_name'])
        if fcm_token:
            user.fcm_token = fcm_token
            user.save(update_fields=['fcm_token'])

        tokens = get_tokens_for_user(user)
        tokens['is_new_user'] = created
        return ok(tokens, message='OTP verified')
