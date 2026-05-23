"""
Legacy permission shims — kept for back-compat with existing imports.
Prefer `apps.core.permissions` for new code.
"""
from rest_framework.permissions import BasePermission, SAFE_METHODS


class IsAdminUser(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return (
            u.is_authenticated
            and u.role in ('admin', 'branch_manager', 'support')
            and (u.role != 'support' or request.method in SAFE_METHODS)
        )


class IsDriverUser(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role in ('driver', 'preparer')


class IsCustomerUser(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'customer'


class IsAdminOrDriver(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role in ('admin', 'driver', 'preparer', 'branch_manager')


class IsOwnerOrAdmin(BasePermission):
    def has_object_permission(self, request, view, obj):
        if request.user.role in ('admin', 'branch_manager'):
            return True
        return hasattr(obj, 'user') and obj.user == request.user
