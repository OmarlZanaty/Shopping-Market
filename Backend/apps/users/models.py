from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.db import models
from django.utils.translation import gettext_lazy as _
import uuid


class UserManager(BaseUserManager):
    def create_user(self, phone, password=None, **extra_fields):
        if not phone:
            raise ValueError(_('Phone number is required'))
        user = self.model(phone=phone, **extra_fields)
        if password:
            user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password, **extra_fields):
        extra_fields.setdefault('role', User.Role.ADMIN)
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        return self.create_user(phone, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    class Role(models.TextChoices):
        CUSTOMER = 'customer', _('Customer')
        PREPARER = 'preparer', _('Preparer')
        DRIVER = 'driver', _('Driver')
        ADMIN = 'admin', _('Admin / Super Admin')
        BRANCH_MANAGER = 'branch_manager', _('Branch Manager')
        SUPPORT = 'support', _('Support (Read-only)')

    class LoginType(models.TextChoices):
        PHONE = 'phone', _('Phone')
        OTP = 'otp', _('OTP')
        GOOGLE = 'google', _('Google')
        FACEBOOK = 'facebook', _('Facebook')
        APPLE = 'apple', _('Apple')
        BIOMETRIC = 'biometric', _('Biometric')

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=20, unique=True, db_index=True)
    full_name = models.CharField(max_length=150)
    email = models.EmailField(blank=True, null=True, db_index=True)
    avatar = models.ImageField(upload_to='avatars/', null=True, blank=True)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.CUSTOMER)
    login_type = models.CharField(max_length=20, choices=LoginType.choices, default=LoginType.PHONE)
    social_id = models.CharField(max_length=200, blank=True, null=True)

    # Multi-store scope. NULL for customers (global account) and Super Admin.
    store = models.ForeignKey(
        'stores.Store', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='staff_users',
    )

    # Wallet & Points (global, cross-store)
    wallet_balance = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    loyalty_points = models.PositiveIntegerField(default=0)

    # Location (driver)
    current_latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    current_longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    is_online = models.BooleanField(default=False)
    last_seen = models.DateTimeField(null=True, blank=True)

    # Staff scope
    branch = models.ForeignKey(
        'branches.Branch', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='staff_users',
    )

    # Driver-specific
    id_card_image = models.ImageField(upload_to='driver_ids/', null=True, blank=True)
    delivery_zone = models.CharField(max_length=200, blank=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=5.0)
    total_deliveries = models.PositiveIntegerField(default=0)
    avg_delivery_minutes = models.PositiveIntegerField(default=0)
    cash_on_hand = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Auth status
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    is_blocked = models.BooleanField(default=False)
    block_reason = models.TextField(blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
    biometric_token = models.CharField(max_length=500, blank=True, null=True)
    fcm_token = models.CharField(max_length=500, blank=True, null=True)

    # Gamification
    order_streak = models.PositiveIntegerField(default=0)
    last_order_date = models.DateField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = 'phone'
    REQUIRED_FIELDS = ['full_name']
    objects = UserManager()

    class Meta:
        verbose_name = _('User')
        verbose_name_plural = _('Users')
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['phone']),
            models.Index(fields=['email']),
            models.Index(fields=['role']),
            models.Index(fields=['is_online']),
            models.Index(fields=['store', 'role']),
            models.Index(fields=['branch', 'role']),
        ]

    def __str__(self):
        return f'{self.full_name} ({self.phone}) [{self.role}]'

    @property
    def is_driver(self):
        return self.role == self.Role.DRIVER

    @property
    def is_preparer(self):
        return self.role == self.Role.PREPARER

    @property
    def is_agent(self):
        return self.role in (self.Role.PREPARER, self.Role.DRIVER)

    @property
    def is_customer(self):
        return self.role == self.Role.CUSTOMER

    @property
    def is_admin_user(self):
        return self.role == self.Role.ADMIN

    @property
    def is_super_admin(self):
        return self.role == self.Role.ADMIN and self.store_id is None

    @property
    def is_store_admin(self):
        return self.role == self.Role.ADMIN and self.store_id is not None


class Address(models.Model):
    class Label(models.TextChoices):
        HOME = 'home', _('Home')
        WORK = 'work', _('Work')
        OTHER = 'other', _('Other')

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='addresses')
    label = models.CharField(max_length=20, choices=Label.choices, default=Label.HOME)
    full_address = models.TextField()
    building_number = models.CharField(max_length=20)
    floor_number = models.CharField(max_length=10)
    apartment_number = models.CharField(max_length=10)
    landmark = models.CharField(max_length=200, blank=True)
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-is_default', '-created_at']
        indexes = [models.Index(fields=['user', 'is_default'])]

    def __str__(self):
        return f'{self.user.full_name} - {self.label}'

    def save(self, *args, **kwargs):
        if self.is_default:
            Address.objects.filter(user=self.user, is_default=True).exclude(pk=self.pk).update(is_default=False)
        super().save(*args, **kwargs)


class PointsTransaction(models.Model):
    class TransactionType(models.TextChoices):
        EARNED = 'earned', _('Earned')
        REDEEMED = 'redeemed', _('Redeemed')
        BONUS = 'bonus', _('Bonus')
        EXPIRED = 'expired', _('Expired')

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='points_transactions')
    transaction_type = models.CharField(max_length=20, choices=TransactionType.choices)
    points = models.IntegerField()
    balance_after = models.PositiveIntegerField()
    description = models.CharField(max_length=200)
    order = models.ForeignKey('orders.Order', null=True, blank=True, on_delete=models.SET_NULL)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['user', '-created_at'])]


class WalletTransaction(models.Model):
    """Spec table — wallet ledger (separate from PointsTransaction)."""

    class Type(models.TextChoices):
        CREDIT = 'credit', _('Credit')
        DEBIT = 'debit', _('Debit')

    class Reason(models.TextChoices):
        REFUND = 'refund', _('Refund')
        ORDER_PAYMENT = 'order_payment', _('Order Payment')
        ADMIN_CREDIT = 'admin_credit', _('Admin Credit')
        POINTS_REDEMPTION = 'points_redemption', _('Points Redemption')
        POINTS_EARNED = 'points_earned', _('Points Earned')

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='wallet_transactions')
    type = models.CharField(max_length=10, choices=Type.choices)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    reason = models.CharField(max_length=30, choices=Reason.choices)
    reference_id = models.CharField(max_length=100, blank=True)  # UUID/INT as string
    reference_type = models.CharField(max_length=50, blank=True)
    balance_after = models.DecimalField(max_digits=10, decimal_places=2)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['type', '-created_at']),
        ]

    def __str__(self):
        return f'{self.user.phone} {self.type} {self.amount} ({self.reason})'


class DataShareLog(models.Model):
    """Driver shares customer data — privacy audit trail."""
    driver = models.ForeignKey(User, on_delete=models.CASCADE, related_name='share_logs')
    customer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='data_shared_logs')
    order = models.ForeignKey('orders.Order', on_delete=models.CASCADE)
    share_method = models.CharField(max_length=50)  # whatsapp, sms, copy
    shared_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-shared_at']


class OTPCode(models.Model):
    """Stores hashed OTP codes for phone verification."""
    phone = models.CharField(max_length=20, db_index=True)
    code_hash = models.CharField(max_length=128)  # SHA-256
    attempts = models.PositiveIntegerField(default=0)
    is_used = models.BooleanField(default=False)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['phone', 'is_used', 'expires_at']),
        ]
