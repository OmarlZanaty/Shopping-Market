from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _


class AdminPermission(models.TextChoices):
    # Orders
    VIEW_ORDERS = 'view_orders', _('View Orders')
    MANAGE_ORDERS = 'manage_orders', _('Manage Orders')
    ASSIGN_DRIVERS = 'assign_drivers', _('Assign Drivers')
    CANCEL_ORDERS = 'cancel_orders', _('Cancel Orders')
    # Products
    VIEW_PRODUCTS = 'view_products', _('View Products')
    MANAGE_PRODUCTS = 'manage_products', _('Manage Products')
    MANAGE_CATEGORIES = 'manage_categories', _('Manage Categories')
    MANAGE_BANNERS = 'manage_banners', _('Manage Banners')
    MANAGE_MEDIA = 'manage_media', _('Manage Media Library')
    # Users
    VIEW_CUSTOMERS = 'view_customers', _('View Customers')
    MANAGE_CUSTOMERS = 'manage_customers', _('Manage Customers')
    VIEW_DRIVERS = 'view_drivers', _('View Drivers')
    MANAGE_DRIVERS = 'manage_drivers', _('Manage Drivers')
    SETTLE_CASH = 'settle_cash', _('Settle Driver Cash')
    # Analytics
    VIEW_ANALYTICS = 'view_analytics', _('View Analytics')
    VIEW_REPORTS = 'view_reports', _('View Reports')
    EXPORT_REPORTS = 'export_reports', _('Export Reports')
    # Settings
    MANAGE_SETTINGS = 'manage_settings', _('Manage App Settings')
    MANAGE_BRANCHES = 'manage_branches', _('Manage Branches')
    SEND_NOTIFICATIONS = 'send_notifications', _('Send Notifications')
    # Admin management (SUPER ADMIN ONLY)
    MANAGE_ADMINS = 'manage_admins', _('Manage Admin Accounts')
    VIEW_AUDIT_LOG = 'view_audit_log', _('View Audit Log')


PERMISSION_GROUPS = {
    'orders': [
        AdminPermission.VIEW_ORDERS,
        AdminPermission.MANAGE_ORDERS,
        AdminPermission.ASSIGN_DRIVERS,
        AdminPermission.CANCEL_ORDERS,
    ],
    'products': [
        AdminPermission.VIEW_PRODUCTS,
        AdminPermission.MANAGE_PRODUCTS,
        AdminPermission.MANAGE_CATEGORIES,
        AdminPermission.MANAGE_BANNERS,
        AdminPermission.MANAGE_MEDIA,
    ],
    'users': [
        AdminPermission.VIEW_CUSTOMERS,
        AdminPermission.MANAGE_CUSTOMERS,
        AdminPermission.VIEW_DRIVERS,
        AdminPermission.MANAGE_DRIVERS,
        AdminPermission.SETTLE_CASH,
    ],
    'analytics': [
        AdminPermission.VIEW_ANALYTICS,
        AdminPermission.VIEW_REPORTS,
        AdminPermission.EXPORT_REPORTS,
    ],
    'settings': [
        AdminPermission.MANAGE_SETTINGS,
        AdminPermission.MANAGE_BRANCHES,
        AdminPermission.SEND_NOTIFICATIONS,
    ],
    'superadmin': [
        AdminPermission.MANAGE_ADMINS,
        AdminPermission.VIEW_AUDIT_LOG,
    ],
}

# Preset roles with default permissions
PRESET_ROLES = {
    'super_admin': {
        'label_ar': 'مدير عام',
        'label_en': 'Super Admin',
        'permissions': list(AdminPermission),
    },
    'manager': {
        'label_ar': 'مدير',
        'label_en': 'Branch Manager',
        'permissions': [
            AdminPermission.VIEW_ORDERS, AdminPermission.MANAGE_ORDERS,
            AdminPermission.ASSIGN_DRIVERS, AdminPermission.VIEW_PRODUCTS,
            AdminPermission.MANAGE_PRODUCTS, AdminPermission.VIEW_DRIVERS,
            AdminPermission.VIEW_ANALYTICS, AdminPermission.VIEW_REPORTS,
            AdminPermission.SETTLE_CASH,
        ],
    },
    'orders_staff': {
        'label_ar': 'موظف طلبات',
        'label_en': 'Orders Staff',
        'permissions': [
            AdminPermission.VIEW_ORDERS, AdminPermission.MANAGE_ORDERS,
            AdminPermission.ASSIGN_DRIVERS, AdminPermission.VIEW_DRIVERS,
        ],
    },
    'products_staff': {
        'label_ar': 'موظف منتجات',
        'label_en': 'Products Staff',
        'permissions': [
            AdminPermission.VIEW_PRODUCTS, AdminPermission.MANAGE_PRODUCTS,
            AdminPermission.MANAGE_CATEGORIES, AdminPermission.MANAGE_MEDIA,
        ],
    },
    'analytics_viewer': {
        'label_ar': 'مشاهد تقارير',
        'label_en': 'Analytics Viewer',
        'permissions': [
            AdminPermission.VIEW_ANALYTICS, AdminPermission.VIEW_REPORTS,
        ],
    },
}


class AdminProfile(models.Model):
    """Extended profile for admin users with role & permissions"""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='admin_profile'
    )
    is_super_admin = models.BooleanField(default=False)
    preset_role = models.CharField(
        max_length=50,
        choices=[(k, v['label_en']) for k, v in PRESET_ROLES.items()],
        blank=True, null=True
    )
    permissions = models.JSONField(default=list)
    allowed_branches = models.ManyToManyField(
        'branches.Branch',
        blank=True,
        help_text='Leave empty for access to all branches'
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name='created_admins'
    )
    notes = models.TextField(blank=True)
    last_login_ip = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Admin Profile'

    def __str__(self):
        return f'{self.user.full_name} [{self.get_preset_role_display() or "Custom"}]'

    def has_permission(self, perm):
        if self.is_super_admin:
            return True
        return perm in self.permissions

    def has_any_permission(self, *perms):
        if self.is_super_admin:
            return True
        return any(p in self.permissions for p in perms)

    def set_preset_role(self, role_key):
        if role_key in PRESET_ROLES:
            self.preset_role = role_key
            role_data = PRESET_ROLES[role_key]
            self.permissions = [p.value for p in role_data['permissions']]
            if role_key == 'super_admin':
                self.is_super_admin = True
            self.save()

    @property
    def all_branches_access(self):
        return not self.allowed_branches.exists()


class AdminAuditLog(models.Model):
    """Track every action performed by admin users"""
    class ActionType(models.TextChoices):
        CREATE = 'create', 'Create'
        UPDATE = 'update', 'Update'
        DELETE = 'delete', 'Delete'
        LOGIN = 'login', 'Login'
        LOGOUT = 'logout', 'Logout'
        BLOCK = 'block', 'Block/Unblock'
        SETTLE = 'settle', 'Cash Settlement'
        ASSIGN = 'assign', 'Assign Driver'
        NOTIFY = 'notify', 'Send Notification'
        EXPORT = 'export', 'Export Data'

    admin = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL, null=True,
        related_name='audit_logs'
    )
    action = models.CharField(max_length=20, choices=ActionType.choices)
    resource_type = models.CharField(max_length=50)  # 'product', 'order', 'user', etc.
    resource_id = models.CharField(max_length=200, blank=True)
    description = models.TextField()
    old_data = models.JSONField(null=True, blank=True)
    new_data = models.JSONField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['admin', 'created_at']),
            models.Index(fields=['resource_type', 'created_at']),
        ]

    def __str__(self):
        return f'{self.admin} | {self.action} | {self.resource_type} | {self.created_at}'


def log_admin_action(admin_user, action, resource_type, resource_id='',
                     description='', old_data=None, new_data=None, request=None):
    """Helper to create audit log entries"""
    ip = None
    if request:
        x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
        ip = x_forwarded.split(',')[0] if x_forwarded else request.META.get('REMOTE_ADDR')
    AdminAuditLog.objects.create(
        admin=admin_user,
        action=action,
        resource_type=resource_type,
        resource_id=str(resource_id),
        description=description,
        old_data=old_data,
        new_data=new_data,
        ip_address=ip,
    )
