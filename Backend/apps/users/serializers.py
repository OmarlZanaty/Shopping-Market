from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate

from .models import User, Address, PointsTransaction, WalletTransaction
from apps.core.validators import validate_egyptian_phone


class AddressSerializer(serializers.ModelSerializer):
    class Meta:
        model = Address
        fields = '__all__'
        read_only_fields = ['user']

    def validate(self, attrs):
        for field in ('building_number', 'floor_number', 'apartment_number'):
            if not (attrs.get(field) or '').strip():
                raise serializers.ValidationError(
                    {field: f'{field} is required (per spec)'}
                )
        return attrs


class UserSerializer(serializers.ModelSerializer):
    addresses = AddressSerializer(many=True, read_only=True)
    avatar_url = serializers.SerializerMethodField()
    is_super_admin = serializers.BooleanField(read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'phone', 'full_name', 'email', 'avatar_url', 'role',
            'store', 'branch',
            'wallet_balance', 'loyalty_points', 'order_streak',
            'is_online', 'rating', 'total_deliveries',
            'is_active', 'is_blocked', 'block_reason',
            'fcm_token', 'addresses', 'is_super_admin',
            'last_seen', 'created_at',
        ]
        read_only_fields = ['id', 'wallet_balance', 'loyalty_points', 'rating',
                            'total_deliveries', 'is_super_admin', 'last_seen']

    def get_avatar_url(self, obj):
        request = self.context.get('request')
        if obj.avatar and request:
            try:
                return request.build_absolute_uri(obj.avatar.url)
            except Exception:
                return None
        return None


class DriverPublicSerializer(serializers.ModelSerializer):
    """Limited driver info for customer (live tracking)."""
    class Meta:
        model = User
        fields = ['id', 'full_name', 'avatar', 'phone', 'rating',
                  'current_latitude', 'current_longitude', 'is_online']


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    confirm_password = serializers.CharField(write_only=True, required=False)

    class Meta:
        model = User
        fields = ['phone', 'full_name', 'password', 'confirm_password',
                  'email', 'login_type', 'social_id', 'role', 'store', 'branch']

    def validate(self, data):
        if 'confirm_password' in data and data.get('password') != data.get('confirm_password'):
            raise serializers.ValidationError({'password': 'Passwords do not match'})
        return data

    def validate_phone(self, value):
        return validate_egyptian_phone(value)

    def create(self, validated_data):
        validated_data.pop('confirm_password', None)
        password = validated_data.pop('password')
        user = User.objects.create_user(password=password, **validated_data)
        return user


class StaffLoginSerializer(serializers.Serializer):
    """Phone + password login for preparer / driver / admin / branch_manager / support."""
    phone = serializers.CharField()
    password = serializers.CharField()

    def validate(self, data):
        cleaned_phone = validate_egyptian_phone(data['phone'])
        user = authenticate(username=cleaned_phone, password=data['password'])
        if not user:
            raise serializers.ValidationError('Invalid phone or password')
        if user.is_blocked:
            raise serializers.ValidationError(f'Account blocked: {user.block_reason}')
        if not user.is_active:
            raise serializers.ValidationError('Account is disabled')
        if user.role == 'customer':
            raise serializers.ValidationError('Customers must use OTP login')
        data['user'] = user
        return data


class SocialLoginSerializer(serializers.Serializer):
    provider = serializers.ChoiceField(choices=['google', 'facebook', 'apple'])
    token = serializers.CharField(required=False, allow_blank=True)  # provider OAuth token
    social_id = serializers.CharField(required=False, allow_blank=True)
    full_name = serializers.CharField(required=False)
    email = serializers.EmailField(required=False)
    phone = serializers.CharField(required=False)

    def validate(self, data):
        provider = data.get('provider')

        if provider == 'apple':
            # Apple's identity must be verified server-side (Guideline 4.8) —
            # never trust a client-supplied social_id/email for this provider.
            from .apple_auth import verify_apple_identity_token, AppleTokenError
            try:
                claims = verify_apple_identity_token(data.get('token', ''))
            except AppleTokenError as e:
                raise serializers.ValidationError({'token': str(e)})
            data['social_id'] = claims['sub']
            if claims.get('email'):
                data['email'] = claims['email']
        elif not data.get('social_id'):
            raise serializers.ValidationError({'social_id': 'This field is required.'})

        social_id = data.get('social_id')
        try:
            user = User.objects.get(social_id=social_id, login_type=provider)
            data['user'] = user
            data['is_new'] = False
        except User.DoesNotExist:
            data['is_new'] = True
        return data


class BiometricLoginSerializer(serializers.Serializer):
    biometric_token = serializers.CharField()

    def validate(self, data):
        try:
            user = User.objects.get(biometric_token=data['biometric_token'], is_active=True)
            data['user'] = user
        except User.DoesNotExist:
            raise serializers.ValidationError('Invalid biometric token')
        return data


class BiometricRegisterSerializer(serializers.Serializer):
    biometric_token = serializers.CharField()


class UpdateFCMTokenSerializer(serializers.Serializer):
    fcm_token = serializers.CharField()


class UpdateLocationSerializer(serializers.Serializer):
    lat = serializers.DecimalField(max_digits=10, decimal_places=7, required=False)
    lng = serializers.DecimalField(max_digits=11, decimal_places=8, required=False)
    # legacy aliases
    latitude = serializers.DecimalField(max_digits=10, decimal_places=7, required=False)
    longitude = serializers.DecimalField(max_digits=11, decimal_places=8, required=False)

    def validate(self, data):
        lat = data.get('lat') or data.get('latitude')
        lng = data.get('lng') or data.get('longitude')
        if lat is None or lng is None:
            raise serializers.ValidationError('lat/lng (or latitude/longitude) required')
        data['lat'] = lat
        data['lng'] = lng
        return data


class DriverSettleSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    notes = serializers.CharField(required=False)


class PointsTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PointsTransaction
        fields = '__all__'


class WalletTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTransaction
        fields = '__all__'


def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {
        'refresh': str(refresh),
        'access': str(refresh.access_token),
        'user': UserSerializer(user).data,
    }
