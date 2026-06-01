from rest_framework import status, generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.core.cache import cache

from .models import User as UserModel, Address, PointsTransaction, DataShareLog, WalletTransaction
from .serializers import (
    RegisterSerializer, StaffLoginSerializer, SocialLoginSerializer,
    BiometricLoginSerializer, BiometricRegisterSerializer,
    UserSerializer, AddressSerializer, UpdateFCMTokenSerializer,
    UpdateLocationSerializer, DriverSettleSerializer,
    PointsTransactionSerializer, WalletTransactionSerializer,
    get_tokens_for_user,
)
from .permissions import IsAdminUser
from apps.core.permissions import IsAgent
from apps.core.responses import ok, fail
from apps.core.throttling import DriverLocationThrottle, StaffLoginThrottle

User = get_user_model()


# ─── Auth ─────────────────────────────────────────────────────────────────────

class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            return ok(get_tokens_for_user(user), message='Registered', status_code=201)
        return fail('Invalid input', errors=serializer.errors, status_code=400)


class StaffLoginView(APIView):
    """phone + password — for preparer / driver / admin / branch_manager / support."""
    permission_classes = [permissions.AllowAny]
    throttle_classes = [StaffLoginThrottle]

    def post(self, request):
        serializer = StaffLoginSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.validated_data['user']
            user.last_seen = timezone.now()
            user.save(update_fields=['last_seen'])
            return ok(get_tokens_for_user(user), message='Logged in')
        return fail('Invalid credentials', errors=serializer.errors, status_code=401)


class SocialLoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = SocialLoginSerializer(data=request.data)
        if not serializer.is_valid():
            return fail('Invalid input', errors=serializer.errors, status_code=400)

        data = serializer.validated_data
        if data.get('is_new'):
            phone = data.get('phone', '')
            if not phone:
                return fail('Phone required for new social signup', status_code=400)
            user = User.objects.create_user(
                phone=phone,
                full_name=data.get('full_name', ''),
                email=data.get('email', ''),
                login_type=data['provider'],
                social_id=data['social_id'],
            )
            created = True
        else:
            user = data['user']
            created = False

        tokens = get_tokens_for_user(user)
        tokens['is_new_user'] = created
        return ok(tokens, message='Social login successful')


class BiometricRegisterView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = BiometricRegisterSerializer(data=request.data)
        if serializer.is_valid():
            request.user.biometric_token = serializer.validated_data['biometric_token']
            request.user.save(update_fields=['biometric_token'])
            return ok({'registered': True})
        return fail('Invalid input', errors=serializer.errors, status_code=400)


class BiometricLoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = BiometricLoginSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.validated_data['user']
            return ok(get_tokens_for_user(user))
        return fail('Invalid biometric', errors=serializer.errors, status_code=401)


class LogoutView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data['refresh']
            RefreshToken(refresh_token).blacklist()
            return ok({'logged_out': True})
        except Exception:
            return fail('Invalid token', status_code=400)


class MeView(generics.RetrieveUpdateAPIView):
    """GET /me — current user profile. PATCH /me — update name/avatar/fcm_token."""
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user

    def update(self, request, *args, **kwargs):
        allowed = {'full_name', 'email', 'fcm_token', 'avatar'}
        payload = {k: v for k, v in request.data.items() if k in allowed}
        ser = UserSerializer(self.get_object(), data=payload, partial=True, context={'request': request})
        if not ser.is_valid():
            return fail('Invalid input', errors=ser.errors, status_code=400)
        ser.save()
        return ok(ser.data)


# Keep legacy name
class ProfileView(MeView):
    pass


class UpdateFCMTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = UpdateFCMTokenSerializer(data=request.data)
        if serializer.is_valid():
            request.user.fcm_token = serializer.validated_data['fcm_token']
            request.user.save(update_fields=['fcm_token'])
            return ok({'fcm_token_updated': True})
        return fail('Invalid input', errors=serializer.errors, status_code=400)


# ─── Driver / Agent location ──────────────────────────────────────────────────

class UpdateLocationView(APIView):
    """
    Spec: driver/preparer pushes lat/lng. Max 1 / 5 seconds.
    Writes to user table + Redis (driver:{id}:location) with 60s TTL.
    Emits to admin WS room.
    """
    permission_classes = [permissions.IsAuthenticated, IsAgent]
    throttle_classes = [DriverLocationThrottle]

    def patch(self, request):
        return self._update(request)

    def post(self, request):  # back-compat
        return self._update(request)

    def _update(self, request):
        serializer = UpdateLocationSerializer(data=request.data)
        if not serializer.is_valid():
            return fail('Invalid input', errors=serializer.errors, status_code=400)
        lat = serializer.validated_data['lat']
        lng = serializer.validated_data['lng']

        u = request.user
        u.current_latitude = lat
        u.current_longitude = lng
        u.is_online = True
        u.last_seen = timezone.now()
        u.save(update_fields=['current_latitude', 'current_longitude', 'is_online', 'last_seen'])

        # Redis cache for fast admin map polling
        cache.set(f'driver:{u.id}:location',
                  {'lat': str(lat), 'lng': str(lng), 'ts': u.last_seen.isoformat()},
                  60)

        # Broadcast asynchronously
        try:
            from apps.orders.tasks import broadcast_driver_location
            broadcast_driver_location.delay(str(u.id))
        except Exception:
            pass
        return ok({'updated': True})


class DriverOnlineToggleView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request):
        request.user.is_online = not request.user.is_online
        request.user.save(update_fields=['is_online'])
        return ok({'is_online': request.user.is_online})


# ─── Addresses ────────────────────────────────────────────────────────────────

class AddressListCreateView(generics.ListCreateAPIView):
    serializer_class = AddressSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Address.objects.filter(user=self.request.user).order_by('-is_default', '-created_at')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class AddressDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = AddressSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Address.objects.filter(user=self.request.user)

    def destroy(self, request, *args, **kwargs):
        # Spec: cannot delete an address attached to an active order
        addr = self.get_object()
        active = addr.orders.exclude(status__in=['delivered', 'cancelled']).exists() \
            if hasattr(addr, 'orders') else False
        if active:
            return fail('Cannot delete address used by an active order', status_code=400)
        return super().destroy(request, *args, **kwargs)


class AddressDefaultView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, pk):
        try:
            addr = Address.objects.get(pk=pk, user=request.user)
        except Address.DoesNotExist:
            return fail('Address not found', status_code=404)
        addr.is_default = True
        addr.save()
        return ok({'id': addr.id, 'is_default': True})


# ─── Wallet ───────────────────────────────────────────────────────────────────

class WalletBalanceView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return ok({
            'wallet_balance': str(request.user.wallet_balance),
            'loyalty_points': request.user.loyalty_points,
        })


class WalletTransactionsView(generics.ListAPIView):
    serializer_class = WalletTransactionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return WalletTransaction.objects.filter(user=self.request.user).order_by('-created_at')


# ─── Admin: staff users + customers ───────────────────────────────────────────

class AdminUserListView(generics.ListAPIView):
    """All STAFF users (preparer/driver/admin/branch_manager/support). Store-scoped."""
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    filterset_fields = ['is_active', 'branch']
    search_fields = ['full_name', 'phone', 'email']

    def get_queryset(self):
        # Role filtering is handled here to support comma-separated values
        # (e.g. ?role=preparer,driver for the Agents page).
        role_param = self.request.query_params.get('role')
        roles = [r.strip() for r in role_param.split(',')] if role_param else []

        if 'customer' in roles:
            qs = User.objects.all()
        else:
            qs = User.objects.exclude(role='customer')

        if roles:
            qs = qs.filter(role__in=roles)

        store_id = getattr(self.request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(store_id=store_id)
        return qs.order_by('-created_at')


class AdminUserDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    lookup_field = 'id'

    def get_queryset(self):
        qs = User.objects.all()
        store_id = getattr(self.request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(store_id=store_id)
        return qs


class AdminStaffCreateView(APIView):
    """Admin creates preparer/driver/branch_manager/support."""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def post(self, request):
        allowed_roles = {'preparer', 'driver', 'branch_manager', 'support'}
        data = request.data.copy()
        role = data.get('role')
        if role not in allowed_roles:
            return fail(f'role must be one of {sorted(allowed_roles)}', status_code=400)

        # Force store scope for store-admins
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            data['store'] = store_id

        serializer = RegisterSerializer(data=data)
        if serializer.is_valid():
            user = serializer.save(role=role)
            return ok(UserSerializer(user, context={'request': request}).data,
                      message='Staff created', status_code=201)
        return fail('Invalid input', errors=serializer.errors, status_code=400)


class AdminBlockUserView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def patch(self, request, pk):
        try:
            user = User.objects.get(pk=pk)
        except User.DoesNotExist:
            return fail('User not found', status_code=404)
        # Prevent cross-store muto for store-admins
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None and user.store_id and user.store_id != store_id:
            return fail('Cannot modify user in another store', status_code=403)

        block = bool(request.data.get('block', True))
        reason = request.data.get('reason', '')
        user.is_blocked = block
        user.block_reason = reason if block else ''
        user.is_active = not block
        user.save(update_fields=['is_blocked', 'block_reason', 'is_active'])
        return ok({'id': str(user.id), 'is_blocked': user.is_blocked, 'is_active': user.is_active})


class AdminCustomerListView(generics.ListAPIView):
    """Customers are GLOBAL (no store scoping). Only super-admin or any admin can browse."""
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]
    search_fields = ['full_name', 'phone', 'email']

    def get_queryset(self):
        return User.objects.filter(role='customer').order_by('-created_at')


class AdminCustomerWalletAdjustView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def post(self, request, pk):
        try:
            customer = User.objects.get(pk=pk, role='customer')
        except User.DoesNotExist:
            return fail('Customer not found', status_code=404)
        try:
            amount = float(request.data['amount'])
            txn_type = request.data['type']  # 'credit' or 'debit'
        except (KeyError, TypeError, ValueError):
            return fail('amount and type required', status_code=400)
        if txn_type not in ('credit', 'debit'):
            return fail('type must be credit or debit', status_code=400)
        reason = request.data.get('reason', 'admin_credit')

        if txn_type == 'credit':
            customer.wallet_balance = float(customer.wallet_balance) + amount
        else:
            if float(customer.wallet_balance) < amount:
                return fail('Insufficient wallet balance', status_code=400)
            customer.wallet_balance = float(customer.wallet_balance) - amount
        customer.save(update_fields=['wallet_balance'])

        WalletTransaction.objects.create(
            user=customer,
            type=txn_type,
            amount=amount,
            reason=reason,
            balance_after=customer.wallet_balance,
            reference_type='admin_action',
            reference_id=str(request.user.id),
        )
        return ok({'wallet_balance': str(customer.wallet_balance)})


class AdminDriversLiveView(APIView):
    """Live driver locations. Reads from Redis where available, falls back to DB."""
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        qs = User.objects.filter(role='driver', is_active=True)
        store_id = getattr(request.user, 'store_id', None)
        if store_id is not None:
            qs = qs.filter(store_id=store_id)
        result = []
        for d in qs:
            cached = cache.get(f'driver:{d.id}:location')
            if cached:
                result.append({
                    'id': str(d.id),
                    'name': d.full_name,
                    'phone': d.phone,
                    'rating': str(d.rating),
                    'is_online': d.is_online,
                    'lat': cached.get('lat'),
                    'lng': cached.get('lng'),
                    'last_update': cached.get('ts'),
                })
            else:
                result.append({
                    'id': str(d.id),
                    'name': d.full_name,
                    'phone': d.phone,
                    'rating': str(d.rating),
                    'is_online': d.is_online,
                    'lat': str(d.current_latitude or 0),
                    'lng': str(d.current_longitude or 0),
                    'last_update': d.last_seen.isoformat() if d.last_seen else None,
                })
        return ok(result)


class AdminSettleCashView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def post(self, request, pk):
        try:
            driver = User.objects.get(pk=pk, role='driver')
        except User.DoesNotExist:
            return fail('Driver not found', status_code=404)
        serializer = DriverSettleSerializer(data=request.data)
        if serializer.is_valid():
            amount = float(serializer.validated_data['amount'])
            driver.cash_on_hand = max(0, float(driver.cash_on_hand) - amount)
            driver.save(update_fields=['cash_on_hand'])
            return ok({
                'settled': amount,
                'remaining_cash': str(driver.cash_on_hand),
            })
        return fail('Invalid input', errors=serializer.errors, status_code=400)


class PointsHistoryView(generics.ListAPIView):
    serializer_class = PointsTransactionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return PointsTransaction.objects.filter(user=self.request.user).order_by('-created_at')


class DataShareLogView(APIView):
    """Driver logs sharing customer data."""
    permission_classes = [permissions.IsAuthenticated, IsAgent]

    def post(self, request):
        DataShareLog.objects.create(
            driver=request.user,
            customer_id=request.data.get('customer_id'),
            order_id=request.data.get('order_id'),
            share_method=request.data.get('method', 'whatsapp'),
        )
        return ok({'logged': True})
