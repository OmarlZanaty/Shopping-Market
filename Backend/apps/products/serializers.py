from rest_framework import serializers

from .models import Product, Category, Banner, MediaLibrary, ProductImage, ProductBranch
from apps.core.validators import validate_image_upload, validate_hex_color


class CategorySerializer(serializers.ModelSerializer):
    product_count = serializers.SerializerMethodField()

    class Meta:
        model = Category
        fields = '__all__'
        extra_kwargs = {
            # store is injected server-side (enforce_store_id_on_create)
            'store': {'required': False},
        }

    def get_product_count(self, obj):
        return obj.products.filter(is_available=True).count()

    def validate_color_hex(self, value):
        return validate_hex_color(value) or ''


class ProductImageSerializer(serializers.ModelSerializer):
    image_url_full = serializers.SerializerMethodField()

    class Meta:
        model = ProductImage
        fields = '__all__'

    def get_image_url_full(self, obj):
        if obj.image_url:
            return obj.image_url
        request = self.context.get('request')
        if obj.image and request:
            try:
                return request.build_absolute_uri(obj.image.url)
            except Exception:
                pass
        return ''

    def validate_image(self, value):
        return validate_image_upload(value)


class ProductBranchSerializer(serializers.ModelSerializer):
    branch_name = serializers.CharField(source='branch.name', read_only=True)

    class Meta:
        model = ProductBranch
        fields = ['id', 'branch', 'branch_name', 'stock_quantity', 'is_available', 'updated_at']


class ProductListSerializer(serializers.ModelSerializer):
    current_price = serializers.ReadOnlyField()
    discount_percentage_calc = serializers.ReadOnlyField(source='computed_discount_percentage')
    category_ids = serializers.SerializerMethodField()
    main_image_url = serializers.SerializerMethodField()
    is_on_sale = serializers.SerializerMethodField()
    unit_type = serializers.CharField(source='sell_unit', read_only=True)

    class Meta:
        model = Product
        fields = [
            'id', 'store', 'barcode', 'name_ar', 'name_en',
            'original_price', 'discount_price', 'discount_percentage',
            'discount_percentage_calc', 'current_price',
            'unit_type', 'sell_unit', 'is_weight_based',
            'is_available', 'is_featured',
            'quantity_in_stock', 'low_stock_threshold',
            'category_ids', 'main_image_url', 'is_on_sale',
            'discount_start', 'discount_end',
        ]

    def get_category_ids(self, obj):
        return list(obj.categories.values_list('id', flat=True))

    def get_main_image_url(self, obj):
        if obj.image_url_s3:
            return obj.image_url_s3
        if obj.main_image:
            request = self.context.get('request')
            if request:
                try:
                    return request.build_absolute_uri(obj.main_image.url)
                except Exception:
                    pass
        return ''

    def get_is_on_sale(self, obj):
        return obj.current_price < obj.original_price


class ProductSerializer(ProductListSerializer):
    images = ProductImageSerializer(many=True, read_only=True)
    categories = CategorySerializer(many=True, read_only=True)
    branch_stock = ProductBranchSerializer(many=True, read_only=True)
    alternatives = serializers.SerializerMethodField()
    related = serializers.SerializerMethodField()
    savings = serializers.ReadOnlyField()
    waitlist_count = serializers.SerializerMethodField()

    class Meta(ProductListSerializer.Meta):
        fields = ProductListSerializer.Meta.fields + [
            'description_ar', 'description_en', 'categories', 'images',
            'branch_stock', 'cost_price', 'weight_tolerance_pct',
            'min_order_quantity', 'max_order_quantity',
            'alternatives', 'related', 'savings', 'waitlist_count',
            'is_out_of_stock', 'is_low_stock',
        ]

    def get_alternatives(self, obj):
        alts = obj.alternative_products.filter(is_available=True)[:5]
        return ProductListSerializer(alts, many=True, context=self.context).data

    def get_related(self, obj):
        related = obj.related_products.filter(is_available=True)[:6]
        return ProductListSerializer(related, many=True, context=self.context).data

    def get_waitlist_count(self, obj):
        return obj.waitlist.filter(notified_at__isnull=True).count()


class ProductCreateSerializer(serializers.ModelSerializer):
    category_ids = serializers.ListField(
        child=serializers.IntegerField(), write_only=True, required=False)
    alternative_ids = serializers.ListField(
        child=serializers.UUIDField(), write_only=True, required=False)
    related_ids = serializers.ListField(
        child=serializers.UUIDField(), write_only=True, required=False)
    branch_stock_items = serializers.ListField(
        child=serializers.DictField(), write_only=True, required=False,
        help_text='[{branch_id, stock_quantity}, ...]',
    )

    class Meta:
        model = Product
        fields = '__all__'
        extra_kwargs = {
            'categories': {'required': False},
            'alternative_products': {'required': False},
            'related_products': {'required': False},
        }

    def validate_main_image(self, value):
        return validate_image_upload(value)

    def create(self, validated_data):
        category_ids = validated_data.pop('category_ids', [])
        alternative_ids = validated_data.pop('alternative_ids', [])
        related_ids = validated_data.pop('related_ids', [])
        branch_stock = validated_data.pop('branch_stock_items', [])
        product = Product.objects.create(**validated_data)
        self._set_m2m(product, category_ids, alternative_ids, related_ids, branch_stock)
        return product

    def update(self, instance, validated_data):
        category_ids = validated_data.pop('category_ids', None)
        alternative_ids = validated_data.pop('alternative_ids', None)
        related_ids = validated_data.pop('related_ids', None)
        branch_stock = validated_data.pop('branch_stock_items', None)
        for attr, val in validated_data.items():
            setattr(instance, attr, val)
        instance.save()
        self._set_m2m(instance, category_ids, alternative_ids, related_ids, branch_stock)
        return instance

    def _set_m2m(self, product, category_ids, alternative_ids, related_ids, branch_stock):
        if category_ids is not None:
            # Categories must belong to the same store
            valid = Category.objects.filter(id__in=category_ids, store_id=product.store_id)
            product.categories.set(valid)
        if alternative_ids is not None:
            valid = Product.objects.filter(id__in=alternative_ids, store_id=product.store_id)
            product.alternative_products.set(valid)
        if related_ids is not None:
            valid = Product.objects.filter(id__in=related_ids, store_id=product.store_id)
            product.related_products.set(valid)
        if branch_stock is not None:
            from apps.branches.models import Branch
            for entry in branch_stock:
                try:
                    branch_id = int(entry.get('branch_id'))
                    qty = int(entry.get('stock_quantity', 0))
                except (TypeError, ValueError):
                    continue
                if Branch.objects.filter(id=branch_id, store_id=product.store_id).exists():
                    ProductBranch.objects.update_or_create(
                        product=product, branch_id=branch_id,
                        defaults={'stock_quantity': qty},
                    )


class BannerSerializer(serializers.ModelSerializer):
    is_currently_active = serializers.ReadOnlyField()
    ctr = serializers.ReadOnlyField()

    class Meta:
        model = Banner
        fields = '__all__'
        extra_kwargs = {
            # store is injected server-side (enforce_store_id_on_create)
            'store': {'required': False},
        }

    def validate_image(self, value):
        return validate_image_upload(value)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Resolve a usable image_url from the uploaded file when not set explicitly.
        if not data.get('image_url') and instance.image:
            request = self.context.get('request')
            try:
                url = instance.image.url
                data['image_url'] = request.build_absolute_uri(url) if request else url
            except Exception:
                pass
        return data


class MediaLibrarySerializer(serializers.ModelSerializer):
    class Meta:
        model = MediaLibrary
        fields = '__all__'
        read_only_fields = ['uploaded_by', 'use_count']

    def validate_image(self, value):
        return validate_image_upload(value)
