from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

User = get_user_model()


class Command(BaseCommand):
    help = 'Create initial data: admin user, sample categories, app settings'

    def handle(self, *args, **kwargs):
        self._create_admin()
        self._create_categories()
        self._create_app_settings()
        self._create_branch()
        self.stdout.write(self.style.SUCCESS('✅ Initial data created'))

    def _create_admin(self):
        if not User.objects.filter(role='admin').exists():
            User.objects.create_superuser(
                phone='01000000000',
                password='Admin@123',
                full_name='System Admin',
                role='admin',
            )
            self.stdout.write('✅ Admin created: phone=01000000000, password=Admin@123')
        else:
            self.stdout.write('ℹ️  Admin already exists')

    def _create_categories(self):
        from apps.products.models import Category
        categories = [
            {'name_ar': 'خضروات', 'name_en': 'Vegetables', 'icon': '🥦', 'sort_order': 1},
            {'name_ar': 'فواكه', 'name_en': 'Fruits', 'icon': '🍎', 'sort_order': 2},
            {'name_ar': 'ألبان وبيض', 'name_en': 'Dairy & Eggs', 'icon': '🥛', 'sort_order': 3},
            {'name_ar': 'لحوم ودواجن', 'name_en': 'Meat & Poultry', 'icon': '🥩', 'sort_order': 4},
            {'name_ar': 'مخبوزات', 'name_en': 'Bakery', 'icon': '🍞', 'sort_order': 5},
            {'name_ar': 'مشروبات', 'name_en': 'Beverages', 'icon': '🧃', 'sort_order': 6},
            {'name_ar': 'منظفات', 'name_en': 'Cleaning', 'icon': '🧴', 'sort_order': 7},
            {'name_ar': 'عناية شخصية', 'name_en': 'Personal Care', 'icon': '🪥', 'sort_order': 8},
            {'name_ar': 'أطفال', 'name_en': 'Baby & Kids', 'icon': '👶', 'sort_order': 9},
            {'name_ar': 'بقالة', 'name_en': 'Grocery', 'icon': '🛒', 'sort_order': 10},
            {'name_ar': 'عروض الأسبوع', 'name_en': 'Weekly Deals', 'icon': '🔥', 'sort_order': 11},
            {'name_ar': 'أكثر مبيعاً', 'name_en': 'Best Sellers', 'icon': '⭐', 'sort_order': 12},
        ]
        created = 0
        for cat in categories:
            _, c = Category.objects.get_or_create(name_en=cat['name_en'], defaults=cat)
            if c:
                created += 1
        self.stdout.write(f'✅ {created} categories created')

    def _create_app_settings(self):
        from apps.notifications.models import AppSettings
        settings_data = [
            {'key': 'support_phone_1', 'value': '01126555088', 'description': 'Customer support phone 1'},
            {'key': 'support_phone_2', 'value': '01126544999', 'description': 'Customer support phone 2'},
            {'key': 'whatsapp_number', 'value': '01126555088', 'description': 'WhatsApp support number'},
            {'key': 'delivery_fee', 'value': '15', 'description': 'Default delivery fee in EGP'},
            {'key': 'min_order_amount', 'value': '50', 'description': 'Minimum order amount in EGP'},
            {'key': 'points_per_egp', 'value': '1', 'description': 'Points earned per EGP'},
            {'key': 'points_value_egp', 'value': '0.05', 'description': 'EGP value per point'},
            {'key': 'app_name_ar', 'value': 'Shopping Market', 'description': 'App name in Arabic'},
            {'key': 'app_name_en', 'value': 'Market Fresh', 'description': 'App name in English'},
            {'key': 'working_hours', 'value': '08:00-00:00', 'description': 'Working hours'},
            {'key': 'auto_close_hours', 'value': '2', 'description': 'Hours before auto-closing delivered order'},
        ]
        created = 0
        for s in settings_data:
            _, c = AppSettings.objects.get_or_create(key=s['key'], defaults=s)
            if c:
                created += 1
        self.stdout.write(f'✅ {created} app settings created')

    def _create_branch(self):
        from apps.branches.models import Branch
        from django.utils import timezone
        import datetime
        if not Branch.objects.exists():
            Branch.objects.create(
                name='Main Branch',
                name_ar='الفرع الرئيسي',
                address='Cairo, Egypt',
                latitude=30.0444,
                longitude=31.2357,
                phone='01000000000',
                delivery_radius_km=15,
                delivery_fee=15,
                opening_time=datetime.time(8, 0),
                closing_time=datetime.time(0, 0),
            )
            self.stdout.write('✅ Main branch created')

    def _setup_super_admin_profile(self):
        """Create AdminProfile for the default super admin"""
        try:
            from apps.users.admin_roles import AdminProfile, PRESET_ROLES
            admin = User.objects.get(phone='01000000000', role='admin')
            profile, created = AdminProfile.objects.get_or_create(
                user=admin,
                defaults={
                    'is_super_admin': True,
                    'preset_role': 'super_admin',
                    'permissions': [p.value for p in list(__import__('apps.users.admin_roles', fromlist=['AdminPermission']).AdminPermission)],
                    'notes': 'Default system super admin',
                }
            )
            if created:
                self.stdout.write('✅ Super admin profile created')
        except Exception as e:
            self.stdout.write(f'⚠️  AdminProfile setup: {e}')
