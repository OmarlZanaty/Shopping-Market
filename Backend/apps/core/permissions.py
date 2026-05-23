"""
Spec-aligned permission classes that respect multi-store scoping.

Role → store_id semantics:
- Super Admin: role='admin' AND store_id IS NULL — sees all stores
- Store Admin: role='admin' AND store_id IS NOT NULL — sees only own store
- Branch Manager: role='branch_manager' AND store_id IS NOT NULL — sees own branch within store
- Preparer/Driver (agent): role IN ('preparer','driver') AND store_id IS NOT NULL — scoped to store + assigned orders
- Support: role='support' AND store_id IS NOT NULL — read-only within store
- Customer: role='customer' AND store_id IS NULL — global; cross-store orders
"""
from rest_framework.permissions import BasePermission, SAFE_METHODS


class IsCustomer(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role == 'customer'


class IsAgent(BasePermission):
    """Preparer or driver — interchangeable for many endpoints."""
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role in ('preparer', 'driver')


class IsPreparer(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role == 'preparer'


class IsDriver(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role == 'driver'


class IsAnyAdmin(BasePermission):
    """Any admin tier: super, store admin, branch manager, or support."""
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role in ('admin', 'branch_manager', 'support')


class IsSuperAdmin(BasePermission):
    """role=admin AND store_id IS NULL"""
    def has_permission(self, request, view):
        u = request.user
        return (
            u.is_authenticated
            and u.role == 'admin'
            and getattr(u, 'store_id', None) is None
        )


class IsStoreAdmin(BasePermission):
    """Admin scoped to a specific store. Super Admin also passes."""
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role == 'admin'


class IsBranchManager(BasePermission):
    def has_permission(self, request, view):
        u = request.user
        return u.is_authenticated and u.role == 'branch_manager'


class IsSupportReadOnly(BasePermission):
    """Support sees data but cannot mutate. Block all unsafe methods."""
    def has_permission(self, request, view):
        u = request.user
        if not u.is_authenticated or u.role != 'support':
            return False
        return request.method in SAFE_METHODS


class IsAdminWriteOrSupportRead(BasePermission):
    """
    Combined: any admin role may read; only admin/branch_manager may write.
    Support is read-only.
    """
    def has_permission(self, request, view):
        u = request.user
        if not u.is_authenticated:
            return False
        if u.role not in ('admin', 'branch_manager', 'support'):
            return False
        if request.method in SAFE_METHODS:
            return True
        return u.role in ('admin', 'branch_manager')
