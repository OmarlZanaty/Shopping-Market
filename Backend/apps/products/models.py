from django.db import models
from django.utils.translation import gettext_lazy as _
from django.utils import timezone
from simple_history.models import HistoricalRecords
import uuid


class Category(models.Model):
    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='categories',
    )

    name_ar = models.CharField(max_length=100)
    name_en = models.CharField(max_length=100)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)

    image = models.ImageField(upload_to='categories/', null=True, blank=True)
    icon = models.CharField(max_length=10, blank=True)  # emoji icon
    icon_url = models.URLField(max_length=500, blank=True)
    color_hex = models.CharField(max_length=7, blank=True)

    parent = models.ForeignKey(
        'self', null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name='children',
    )

    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    is_visible = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['sort_order', 'name_en']
        verbose_name_plural = 'Categories'
        indexes = [
            models.Index(fields=['store', 'is_visible', 'sort_order']),
        ]

    def __str__(self):
        return f'{self.name_en} ({self.store_id})'

    def get_name(self, lang='ar'):
        return self.name_ar if lang == 'ar' else self.name_en


class Product(models.Model):
    class SellUnit(models.TextChoices):
        PIECE = 'piece', _('Piece')
        KG = 'kg', _('Kilogram')
        GRAM = 'gram', _('Gram')
        BOX = 'box', _('Box')
        CARTON = 'carton', _('Carton')
        LITER = 'liter', _('Liter')
        PACK = 'pack', _('Pack')

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='products',
    )

    barcode = models.CharField(max_length=50, unique=True, db_index=True, blank=True, null=True)
    name_ar = models.CharField(max_length=200)
    name_en = models.CharField(max_length=200)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)

    categories = models.ManyToManyField(Category, related_name='products', blank=True)

    # Pricing
    original_price = models.DecimalField(max_digits=10, decimal_places=2)
    discount_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    discount_percentage = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    discount_start = models.DateTimeField(null=True, blank=True)
    discount_end = models.DateTimeField(null=True, blank=True)
    cost_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    # Stock
    quantity_in_stock = models.IntegerField(default=0)
    low_stock_threshold = models.PositiveIntegerField(default=5)
    sell_unit = models.CharField(max_length=20, choices=SellUnit.choices, default=SellUnit.PIECE)
    weight_tolerance_pct = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    is_weight_based = models.BooleanField(default=False)
    min_order_quantity = models.DecimalField(max_digits=6, decimal_places=2, default=1)
    max_order_quantity = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)

    # Status
    is_available = models.BooleanField(default=True)
    is_active = models.BooleanField(default=True)   # False = hidden from customer app
    is_featured = models.BooleanField(default=False)

    # Media
    main_image = models.ImageField(upload_to='products/', null=True, blank=True)
    image_url_s3 = models.URLField(blank=True)
    thumbnail_url = models.URLField(blank=True)

    # Self-relations
    related_products = models.ManyToManyField('self', blank=True, symmetrical=False, related_name='related_to')
    alternative_products = models.ManyToManyField(
        'self', blank=True, symmetrical=True, related_name='alternatives_for'
    )

    # Default branch (legacy single-FK). Use ProductBranch for multi-branch stock.
    branch = models.ForeignKey(
        'branches.Branch', on_delete=models.SET_NULL,
        related_name='primary_for_products',
        null=True, blank=True,
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    history = HistoricalRecords()

    class Meta:
        ordering = ['-is_featured', 'name_en']
        indexes = [
            models.Index(fields=['store', 'is_available']),
            models.Index(fields=['barcode']),
            models.Index(fields=['is_available']),
            models.Index(fields=['discount_end']),
        ]

    def __str__(self):
        return f'{self.name_en} ({self.barcode})'

    def get_name(self, lang='ar'):
        return self.name_ar if lang == 'ar' else self.name_en

    @property
    def current_price(self):
        now = timezone.now()
        if self.discount_price:
            if self.discount_start and self.discount_end:
                if self.discount_start <= now <= self.discount_end:
                    return self.discount_price
            else:
                return self.discount_price
        return self.original_price

    @property
    def computed_discount_percentage(self):
        if self.discount_price and self.original_price > 0:
            return round(((self.original_price - self.current_price) / self.original_price) * 100, 1)
        return 0

    @property
    def savings(self):
        return self.original_price - self.current_price

    @property
    def is_low_stock(self):
        return 0 < self.quantity_in_stock <= self.low_stock_threshold

    @property
    def is_out_of_stock(self):
        return self.quantity_in_stock <= 0


class ProductBranch(models.Model):
    """Per-branch stock — supports the spec's product_branches pivot."""
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='branch_stock')
    branch = models.ForeignKey('branches.Branch', on_delete=models.CASCADE, related_name='product_stock')
    stock_quantity = models.IntegerField(default=0)
    is_available = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('product', 'branch')
        indexes = [
            models.Index(fields=['product', 'branch']),
            models.Index(fields=['branch', 'is_available']),
        ]


class ProductImage(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='images')
    image = models.ImageField(upload_to='products/gallery/')
    image_url = models.URLField(blank=True)
    alt_text_ar = models.CharField(max_length=200, blank=True)
    alt_text_en = models.CharField(max_length=200, blank=True)
    is_primary = models.BooleanField(default=False)
    sort_order = models.PositiveIntegerField(default=0)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-is_primary', 'sort_order']
        indexes = [models.Index(fields=['product', 'is_primary'])]


class MediaLibrary(models.Model):
    """Reusable assets - upload once, use many."""
    name = models.CharField(max_length=200)
    image = models.ImageField(upload_to='media_library/')
    image_url = models.URLField(blank=True)
    thumbnail_url = models.URLField(blank=True)
    file_size = models.PositiveIntegerField(default=0)
    uploaded_by = models.ForeignKey('users.User', on_delete=models.SET_NULL, null=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    use_count = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['-uploaded_at']
        verbose_name_plural = 'Media Library'


class StockWaitlist(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='waitlist')
    user = models.ForeignKey('users.User', on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
    notified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ['product', 'user']
        indexes = [
            models.Index(fields=['product', 'notified_at']),
        ]

    def notify(self):
        from apps.notifications.utils import send_push_notification
        send_push_notification(
            user=self.user,
            title_ar='المنتج متاح الآن!',
            title_en='Product Available!',
            body_ar=f'المنتج {self.product.name_ar} الذي طلبت تنبيهاً عنه متاح الآن',
            body_en=f'{self.product.name_en} you requested is now available',
            data={'type': 'stock_available', 'product_id': str(self.product.id)},
        )
        self.notified_at = timezone.now()
        self.save(update_fields=['notified_at'])


class Banner(models.Model):
    class BannerPosition(models.TextChoices):
        HOME_MAIN = 'home_main', _('Home Main Slider')
        HOME_SECONDARY = 'home_secondary', _('Home Secondary')
        CATEGORY = 'category', _('Category Banner')
        POPUP = 'popup', _('Pop-up on Open')

    class LinkType(models.TextChoices):
        PRODUCT = 'product', _('Product')
        CATEGORY = 'category', _('Category')
        URL = 'url', _('External URL')
        NONE = 'none', _('None')

    store = models.ForeignKey(
        'stores.Store', on_delete=models.CASCADE,
        related_name='banners',
    )

    title_ar = models.CharField(max_length=200)
    title_en = models.CharField(max_length=200)
    subtitle_ar = models.CharField(max_length=300, blank=True)
    subtitle_en = models.CharField(max_length=300, blank=True)
    image = models.ImageField(upload_to='banners/')
    image_url = models.URLField(blank=True)
    position = models.CharField(max_length=30, choices=BannerPosition.choices, default=BannerPosition.HOME_MAIN)

    link_type = models.CharField(max_length=20, choices=LinkType.choices, default=LinkType.NONE)
    link_product = models.ForeignKey(Product, null=True, blank=True, on_delete=models.SET_NULL)
    link_category = models.ForeignKey(Category, null=True, blank=True, on_delete=models.SET_NULL)
    link_url = models.URLField(blank=True)
    link_value = models.CharField(max_length=500, blank=True)

    # Optional branch scope (null = all branches in this store)
    branch = models.ForeignKey(
        'branches.Branch', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='banners',
    )

    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    publish_at = models.DateTimeField(null=True, blank=True)
    start_date = models.DateTimeField(null=True, blank=True)
    expire_at = models.DateTimeField(null=True, blank=True)
    end_date = models.DateTimeField(null=True, blank=True)

    # Analytics
    view_count = models.PositiveIntegerField(default=0)
    click_count = models.PositiveIntegerField(default=0)
    purchase_count = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['position', 'sort_order']
        indexes = [
            models.Index(fields=['store', 'is_active', 'sort_order']),
        ]

    def __str__(self):
        return f'{self.title_en} [{self.position}]'

    @property
    def is_currently_active(self):
        now = timezone.now()
        if not self.is_active:
            return False
        start = self.publish_at or self.start_date
        end = self.expire_at or self.end_date
        if start and now < start:
            return False
        if end and now > end:
            return False
        return True

    @property
    def ctr(self):
        if self.view_count == 0:
            return 0
        return round((self.click_count / self.view_count) * 100, 2)
