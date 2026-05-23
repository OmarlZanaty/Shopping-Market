from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, Address


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ('phone', 'full_name', 'role', 'is_active', 'is_blocked', 'created_at')
    list_filter = ('role', 'is_active', 'is_blocked', 'store')
    search_fields = ('phone', 'full_name', 'email')
    ordering = ('-created_at',)
    readonly_fields = ('id', 'created_at', 'last_seen')

    fieldsets = (
        (None, {'fields': ('id', 'phone', 'password')}),
        ('Personal', {'fields': ('full_name', 'email', 'avatar')}),
        ('Role & Scope', {'fields': ('role', 'store', 'branch')}),
        ('Status', {'fields': ('is_active', 'is_blocked', 'block_reason', 'is_staff', 'is_superuser')}),
        ('Wallet & Points', {'fields': ('wallet_balance', 'loyalty_points')}),
        ('Timestamps', {'fields': ('created_at', 'last_seen')}),
    )
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('phone', 'full_name', 'password1', 'password2', 'role', 'store', 'branch', 'is_active'),
        }),
    )
    # Django's UserAdmin expects username_field
    USERNAME_FIELD = 'phone'


@admin.register(Address)
class AddressAdmin(admin.ModelAdmin):
    list_display = ('user', 'label', 'city', 'is_default')
    search_fields = ('user__phone', 'user__full_name', 'city')
