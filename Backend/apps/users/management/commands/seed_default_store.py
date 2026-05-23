"""
One-shot setup command. Creates:
- A default Store
- Sets multistore_enabled=0 and default_store_id in app_settings
- Creates a Super Admin (store_id=NULL, role=admin)
- Seeds the spec's app_settings keys

Run: python manage.py seed_default_store
"""
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed default store, super admin, and spec app_settings keys'

    def handle(self, *args, **kwargs):
        store = self._create_default_store()
        self._create_super_admin()
        self._create_app_settings(store.id)
        self._create_default_branch(store)
        self._create_default_categories(store)
        self.stdout.write(self.style.SUCCESS('✓ Initial data ready'))

    def _create_default_store(self):
        from apps.stores.models import Store
        store, created = Store.objects.get_or_create(
            name_en='Shopping Market',
            defaults={
                'name_ar': 'شوبينج ماركت',
                'type': 'supermarket',
                'description_ar': 'متجرنا الافتراضي',
                'description_en': 'Default store',
                'primary_color_hex': '#FF6B35',
                'is_active': True,
                'sort_order': 0,
            },
        )
        self.stdout.write(f"{'✓ created' if created else 'ℹ found'} default store: id={store.id}")
        return store

    def _create_super_admin(self):
        if User.objects.filter(role='admin', store__isnull=True).exists():
            self.stdout.write('ℹ super admin already exists')
            return
        u = User.objects.create_superuser(
            phone='01000000000',
            password='Admin@1234',
            full_name='Super Admin',
            role='admin',
            store=None,
        )
        self.stdout.write(f'✓ super admin: phone=01000000000 password=Admin@1234 (id={u.id})')

    def _create_app_settings(self, default_store_id):
        from apps.notifications.models import AppSettings
        settings_data = [
            ('multistore_enabled', '0', 'Show store grid on customer app (1) or single-store mode (0)'),
            ('default_store_id', str(default_store_id), 'Store to load when multistore_enabled=0'),
            ('loyalty_earn_rate', '1', 'Points earned per EGP spent'),
            ('loyalty_redeem_rate', '0.05', 'EGP value per redeemed point'),
            ('min_order_amount', '50', 'Minimum order value (EGP)'),
            ('support_phone_1', '01126555088', 'Customer support phone 1'),
            ('support_phone_2', '01126544999', 'Customer support phone 2'),
            ('whatsapp_number', '01126555088', 'WhatsApp support number'),
            ('app_version_ios', '1.0.0', 'iOS app version'),
            ('app_version_android', '1.0.0', 'Android app version'),
            ('maintenance_mode', '0', 'Service maintenance mode'),
            ('ai_recommendations_enabled', '0', 'AI recommendations feature flag'),
            ('weight_diff_approval_timeout_mins', '15', '15-min approval timeout'),
            ('auto_close_timeout_hours', '2', '2hr auto-close timer'),
            ('delivery_fee', '15', 'Default delivery fee fallback'),
            ('rating_bonus_points', '5', 'Bonus points for rating an order'),
        ]
        created_count = 0
        for key, value, desc in settings_data:
            _, c = AppSettings.objects.get_or_create(
                key=key, defaults={'value': value, 'description': desc},
            )
            if c:
                created_count += 1
        self.stdout.write(f'✓ {created_count} app_settings keys (out of {len(settings_data)})')

    def _create_default_branch(self, store):
        from apps.branches.models import Branch
        if Branch.objects.filter(store=store).exists():
            return
        Branch.objects.create(
            store=store,
            name='Main Branch',
            name_ar='الفرع الرئيسي',
            name_en='Main Branch',
            address='Cairo, Egypt',
            latitude=30.0444,
            longitude=31.2357,
            phone='01000000000',
            delivery_radius_km=15,
            delivery_fee=15,
            operating_hours={'open': '08:00', 'close': '23:59', 'days': [1, 2, 3, 4, 5, 6, 7]},
        )
        self.stdout.write('✓ main branch created')

    def _create_default_categories(self, store):
        from apps.products.models import Category
        if Category.objects.filter(store=store).exists():
            return
        categories = [
            ('خضروات', 'Vegetables', '🥦', 1),
            ('فواكه', 'Fruits', '🍎', 2),
            ('ألبان وبيض', 'Dairy & Eggs', '🥛', 3),
            ('لحوم ودواجن', 'Meat & Poultry', '🥩', 4),
            ('مخبوزات', 'Bakery', '🍞', 5),
            ('مشروبات', 'Beverages', '🧃', 6),
            ('منظفات', 'Cleaning', '🧴', 7),
            ('عناية شخصية', 'Personal Care', '🪥', 8),
            ('أطفال', 'Baby & Kids', '👶', 9),
            ('بقالة', 'Grocery', '🛒', 10),
        ]
        for name_ar, name_en, icon, sort_order in categories:
            Category.objects.create(
                store=store, name_ar=name_ar, name_en=name_en,
                icon=icon, sort_order=sort_order,
            )
        self.stdout.write(f'✓ {len(categories)} default categories created')
