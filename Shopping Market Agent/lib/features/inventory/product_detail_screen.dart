import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_constants.dart';

/// Full product detail / edit screen for the agent.
/// Returns updated [Map<String, dynamic>] on pop if changes were saved.
class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Map<String, dynamic> _data;

  bool _loadingDetail = false;
  bool _saving = false;

  // Form controllers
  late TextEditingController _nameArCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _descArCtrl;

  // Toggles
  bool _isAvailable = true;
  bool _isActive = true;
  bool _isFeatured = false;
  bool _isWeightBased = false;

  // Image
  File? _pickedImage;
  String _imageUrl = '';

  // Extra image gallery (ProductImage rows).
  List<Map<String, dynamic>> _gallery = [];
  bool _galleryBusy = false;

  // Categories (many-to-many — a product can belong to several categories)
  List<Map<String, dynamic>> _allCategories = [];
  final Set<int> _selectedCategoryIds = {};
  bool _loadingCategories = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.product);
    _initFields(_data);
    _loadCategories();
    // If we only have list-level data (missing detail fields), fetch full
    // detail — `categories` is needed to pre-select the product's chips.
    if (!_data.containsKey('is_active') ||
        !_data.containsKey('description_ar') ||
        !_data.containsKey('categories')) {
      _fetchDetail();
    }
  }

  void _initFields(Map<String, dynamic> d) {
    _nameArCtrl = TextEditingController(text: d['name_ar'] ?? '');
    _nameEnCtrl = TextEditingController(text: d['name_en'] ?? '');
    _priceCtrl =
        TextEditingController(text: (d['original_price'] ?? 0).toString());
    _discountCtrl = TextEditingController(
        text: d['discount_price'] != null ? d['discount_price'].toString() : '');
    _stockCtrl = TextEditingController(
        text: (d['quantity_in_stock'] ?? 0).toString());
    _barcodeCtrl = TextEditingController(text: d['barcode'] ?? '');
    _descArCtrl = TextEditingController(text: d['description_ar'] ?? '');
    _isAvailable = d['is_available'] ?? true;
    _isActive = d['is_active'] ?? true;
    _isFeatured = d['is_featured'] ?? false;
    _isWeightBased = d['is_weight_based'] ?? false;
    _imageUrl = d['image_url'] ?? d['image_url_s3'] ?? '';
    _syncGallery(d);
    _syncSelectedCategories(d);
  }

  void _syncGallery(Map<String, dynamic> d) {
    final imgs = d['images'];
    if (imgs is List) {
      _gallery = imgs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }

  String _galleryUrl(Map<String, dynamic> g) =>
      (g['image_url_full'] ?? g['image_url'] ?? '').toString();

  /// Parse the product's current category IDs out of its `categories` list
  /// (`[{id, name_ar, name_en}]`) into [_selectedCategoryIds].
  void _syncSelectedCategories(Map<String, dynamic> d) {
    final cats = d['categories'];
    if (cats is List) {
      _selectedCategoryIds
        ..clear()
        ..addAll(cats
            .whereType<Map>()
            .map((c) => int.tryParse('${c['id']}'))
            .whereType<int>());
    }
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    _stockCtrl.dispose();
    _barcodeCtrl.dispose();
    _descArCtrl.dispose();
    super.dispose();
  }

  // ── Fetch full detail ─────────────────────────────────────────────────────

  Future<void> _fetchDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final res = await DioClient.I.dio
          .get(ApiConstants.inventoryProductDetail(_data['id'].toString()));
      final body = res.data as Map<String, dynamic>;
      final d = (body['data'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;
      setState(() {
        _data = {..._data, ...d};
        _nameArCtrl.text = d['name_ar'] ?? _nameArCtrl.text;
        _nameEnCtrl.text = d['name_en'] ?? _nameEnCtrl.text;
        _priceCtrl.text = (d['original_price'] ?? _priceCtrl.text).toString();
        _discountCtrl.text =
            d['discount_price'] != null ? d['discount_price'].toString() : '';
        _stockCtrl.text =
            (d['quantity_in_stock'] ?? _stockCtrl.text).toString();
        _barcodeCtrl.text = d['barcode'] ?? _barcodeCtrl.text;
        _descArCtrl.text = d['description_ar'] ?? _descArCtrl.text;
        _isAvailable = d['is_available'] ?? _isAvailable;
        _isActive = d['is_active'] ?? _isActive;
        _isFeatured = d['is_featured'] ?? _isFeatured;
        _isWeightBased = d['is_weight_based'] ?? _isWeightBased;
        _imageUrl = d['image_url'] ?? d['image_url_s3'] ?? _imageUrl;
        _syncGallery(d);
        if (d['categories'] is List) _syncSelectedCategories(d);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  // ── Load the store's categories for the multi-select picker ────────────────

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final res = await DioClient.I.dio.get(ApiConstants.inventoryCategories);
      final body = res.data;
      final data = (body is Map && body['data'] is Map)
          ? Map<String, dynamic>.from(body['data'] as Map)
          : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
      final list = (data['categories'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _allCategories =
            list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xfile =
          await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
      if (xfile != null && mounted) {
        setState(() => _pickedImage = File(xfile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل فتح المعرض: $e'),
              backgroundColor: AppColors.errorRed),
        );
      }
    }
  }

  // ── Gallery (multiple images) ──────────────────────────────────────────────

  Future<void> _addGalleryImages() async {
    if (_galleryBusy) return;
    final pid = _data['id']?.toString();
    if (pid == null || pid.isEmpty) return;
    try {
      final picker = ImagePicker();
      final files =
          await picker.pickMultiImage(imageQuality: 80, maxWidth: 1024);
      if (files.isEmpty) return;
      setState(() => _galleryBusy = true);
      final fd = FormData();
      for (final f in files) {
        fd.files.add(MapEntry(
            'images', await MultipartFile.fromFile(f.path)));
      }
      final resp = await DioClient.I.dio
          .post(ApiConstants.inventoryProductImages(pid), data: fd);
      final body = resp.data;
      final list = (body is Map && body['data'] is List)
          ? body['data'] as List
          : (body is List ? body : const []);
      if (!mounted) return;
      setState(() {
        _gallery =
            list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _galleryBusy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _galleryBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('تعذّر رفع الصور'),
            backgroundColor: AppColors.errorRed));
      }
    }
  }

  Future<void> _deleteGalleryImage(int imageId) async {
    final pid = _data['id']?.toString();
    if (pid == null) return;
    try {
      await DioClient.I.dio
          .delete(ApiConstants.inventoryProductImage(pid, imageId));
      if (!mounted) return;
      setState(() => _gallery.removeWhere((g) => g['id'] == imageId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر حذف الصورة'),
            backgroundColor: AppColors.errorRed));
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: AppColors.accentOrange),
              title: const Text('اختر من المعرض',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: AppColors.accentOrange),
              title: const Text('التقط صورة',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_pickedImage != null || _imageUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.errorRed),
                title: const Text('إزالة الصورة',
                    style: TextStyle(color: AppColors.errorRed)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _pickedImage = null;
                    _imageUrl = '';
                  });
                },
              ),
          ]),
        ),
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final discountText = _discountCtrl.text.trim();
      final String? discountPrice =
          discountText.isNotEmpty ? discountText : null;

      // Capture the response so we can read the fresh image_url the backend
      // now returns (with a ?t=<ts> cache-buster) for uploaded images.
      Response resp;
      if (_pickedImage != null) {
        // Has image → multipart
        final formData = FormData.fromMap({
          'name_ar': _nameArCtrl.text.trim(),
          'name_en': _nameEnCtrl.text.trim(),
          'original_price': _priceCtrl.text.trim(),
          'quantity_in_stock': _stockCtrl.text.trim(),
          'is_available': _isAvailable.toString(),
          'is_active': _isActive.toString(),
          'is_featured': _isFeatured.toString(),
          'is_weight_based': _isWeightBased.toString(),
          'description_ar': _descArCtrl.text.trim(),
          if (discountPrice != null) 'discount_price': discountPrice,
          'main_image': await MultipartFile.fromFile(
            _pickedImage!.path,
            filename: 'product_${_data['id']}.jpg',
          ),
        });
        // Categories as repeated form fields → backend reads getlist('category_ids').
        for (final id in _selectedCategoryIds) {
          formData.fields.add(MapEntry('category_ids', id.toString()));
        }
        resp = await DioClient.I.dio.patch(
          ApiConstants.inventoryProductDetail(_data['id'].toString()),
          data: formData,
          options: Options(contentType: 'multipart/form-data'),
        );
      } else {
        // No image → clean JSON
        final body = <String, dynamic>{
          'name_ar': _nameArCtrl.text.trim(),
          'name_en': _nameEnCtrl.text.trim(),
          'original_price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
          'quantity_in_stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
          'is_available': _isAvailable,
          'is_active': _isActive,
          'is_featured': _isFeatured,
          'is_weight_based': _isWeightBased,
          'description_ar': _descArCtrl.text.trim(),
          'discount_price': discountPrice,
          'image_url': _imageUrl,
          'category_ids': _selectedCategoryIds.toList(),
        };
        resp = await DioClient.I.dio.patch(
          ApiConstants.inventoryProductDetail(_data['id'].toString()),
          data: body,
        );
      }

      // ── Extract the new server-side image URL from the response envelope.
      //    Backend returns: { success, data: { image_url, ... } }
      String newImageUrl = _imageUrl;
      try {
        final body = resp.data;
        final data = (body is Map && body['data'] is Map)
            ? Map<String, dynamic>.from(body['data'] as Map)
            : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
        final fromServer = (data['image_url'] ?? '').toString();
        if (fromServer.isNotEmpty) newImageUrl = fromServer;
      } catch (_) {}

      // ── Evict the OLD cached image so CachedNetworkImage can't serve
      //    stale bytes (it caches by URL key, so if the filename happens to
      //    repeat the cache would hide the upload).
      if (_imageUrl.isNotEmpty && _imageUrl != newImageUrl) {
        try {
          await CachedNetworkImage.evictFromCache(_imageUrl);
        } catch (_) {}
      }

      if (!mounted) return;
      // Reflect the new URL locally so the screen shows the fresh image
      // (and drop the picked-file preview now that the server has its copy).
      setState(() {
        _imageUrl = newImageUrl;
        _pickedImage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم الحفظ بنجاح'),
          backgroundColor: AppColors.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Return the updated fields so the grid card refreshes — always pass
      // the SERVER url (with cache-buster) so the parent's Image.network
      // reloads instead of trying to read a now-stale local file path.
      Navigator.of(context).pop({
        'name_ar': _nameArCtrl.text.trim(),
        'name_en': _nameEnCtrl.text.trim(),
        'original_price': double.tryParse(_priceCtrl.text) ?? 0.0,
        'current_price': double.tryParse(_priceCtrl.text) ?? 0.0,
        'quantity_in_stock': int.tryParse(_stockCtrl.text) ?? 0,
        'is_available': _isAvailable,
        'is_active': _isActive,
        'is_featured': _isFeatured,
        'is_weight_based': _isWeightBased,
        'image_url': newImageUrl,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الحفظ: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        title: const Text('تفاصيل المنتج',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (_loadingDetail)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accentOrange)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accentOrange))
                  : const Text('حفظ',
                      style: TextStyle(
                          color: AppColors.accentOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Image ──────────────────────────────────────────────────────────
          _ImageSection(
            imageUrl: _imageUrl,
            pickedImage: _pickedImage,
            onTap: _showImageOptions,
          ),
          const SizedBox(height: 16),

          // ── Extra images gallery ───────────────────────────────────────────
          _SectionCard(
            title: 'صور إضافية',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 84,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final g in _gallery)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: _galleryUrl(g),
                                width: 80, height: 80, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                    width: 80, height: 80,
                                    color: AppColors.backgroundSecondary,
                                    child: const Icon(Icons.broken_image,
                                        color: AppColors.textSecondary)),
                              ),
                            ),
                            Positioned(
                              top: 2, right: 2,
                              child: GestureDetector(
                                onTap: () => _deleteGalleryImage(g['id'] as int),
                                child: Container(
                                  decoration: const BoxDecoration(
                                      color: AppColors.errorRed,
                                      shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      // Add button
                      GestureDetector(
                        onTap: _galleryBusy ? null : _addGalleryImages,
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.divider, width: 1.5),
                          ),
                          child: Center(
                            child: _galleryBusy
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.add_a_photo_outlined,
                                    color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Status toggles ─────────────────────────────────────────────────
          _SectionCard(
            title: 'الحالة',
            children: [
              _ToggleRow(
                label: 'متاح (في المخزون)',
                subtitle: _isAvailable ? 'يظهر كمتوفر للعملاء' : 'يظهر كغير متوفر',
                value: _isAvailable,
                activeColor: AppColors.successGreen,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _ToggleRow(
                label: 'نشط (مرئي للعملاء)',
                subtitle: _isActive
                    ? 'المنتج يظهر في التطبيق'
                    : 'المنتج مخفي تماماً من التطبيق',
                value: _isActive,
                activeColor: AppColors.infoBlue,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _ToggleRow(
                label: 'مميز',
                subtitle: 'يظهر في قسم المنتجات المميزة',
                value: _isFeatured,
                activeColor: AppColors.accentGold,
                onChanged: (v) => setState(() => _isFeatured = v),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _ToggleRow(
                label: 'يُباع بالوزن',
                subtitle: 'السعر يحتسب حسب الوزن الفعلي',
                value: _isWeightBased,
                activeColor: AppColors.purple,
                onChanged: (v) => setState(() => _isWeightBased = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Pricing & stock ────────────────────────────────────────────────
          _SectionCard(
            title: 'السعر والمخزون',
            children: [
              _FormField(
                label: 'السعر الأصلي (ج.م)',
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
              ),
              const Divider(color: AppColors.divider, height: 1),
              _FormField(
                label: 'سعر الخصم (اتركه فارغاً إن لم يكن هناك خصم)',
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
              ),
              const Divider(color: AppColors.divider, height: 1),
              _FormField(
                label: 'الكمية في المخزون',
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Categories (multi-select) ──────────────────────────────────────
          _SectionCard(
            title: 'الفئات',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _loadingCategories
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentOrange)),
                        ),
                      )
                    : _allCategories.isEmpty
                        ? const Align(
                            alignment: Alignment.centerRight,
                            child: Text('لا توجد فئات متاحة',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10, right: 2),
                                child: Text('اختر فئة واحدة أو أكثر',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11)),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _allCategories.map((c) {
                                  final id =
                                      int.tryParse('${c['id']}') ?? -1;
                                  final selected =
                                      _selectedCategoryIds.contains(id);
                                  final name = (c['name_ar'] ??
                                          c['name_en'] ??
                                          '')
                                      .toString();
                                  return FilterChip(
                                    label: Text(name),
                                    selected: selected,
                                    showCheckmark: true,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontSize: 13),
                                    backgroundColor:
                                        AppColors.backgroundPrimary,
                                    selectedColor: AppColors.accentOrange,
                                    side: BorderSide(
                                        color: selected
                                            ? AppColors.accentOrange
                                            : AppColors.divider),
                                    onSelected: (v) => setState(() {
                                      if (v) {
                                        _selectedCategoryIds.add(id);
                                      } else {
                                        _selectedCategoryIds.remove(id);
                                      }
                                    }),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Names ──────────────────────────────────────────────────────────
          _SectionCard(
            title: 'الاسم والوصف',
            children: [
              _FormField(
                label: 'الاسم بالعربية',
                controller: _nameArCtrl,
                textDirection: TextDirection.rtl,
              ),
              const Divider(color: AppColors.divider, height: 1),
              _FormField(
                label: 'الاسم بالإنجليزية',
                controller: _nameEnCtrl,
                textDirection: TextDirection.ltr,
              ),
              const Divider(color: AppColors.divider, height: 1),
              _FormField(
                label: 'الوصف',
                controller: _descArCtrl,
                maxLines: 3,
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Barcode (read-only) ────────────────────────────────────────────
          _SectionCard(
            title: 'الباركود',
            children: [
              _FormField(
                label: 'الباركود',
                controller: _barcodeCtrl,
                readOnly: true,
                textDirection: TextDirection.ltr,
                suffixIcon: Icons.qr_code,
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

// ─── Image section ────────────────────────────────────────────────────────────

class _ImageSection extends StatelessWidget {
  final String imageUrl;
  final File? pickedImage;
  final VoidCallback onTap;
  const _ImageSection(
      {required this.imageUrl,
      required this.pickedImage,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (pickedImage != null) {
      imageWidget = Image.file(pickedImage!, fit: BoxFit.cover);
    } else if (imageUrl.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _imgPlaceholder(),
      );
    } else {
      imageWidget = _imgPlaceholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.divider, style: BorderStyle.solid, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageWidget,
            Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt,
                        color: AppColors.accentOrange, size: 16),
                    SizedBox(width: 4),
                    Text('تغيير الصورة',
                        style: TextStyle(
                            color: AppColors.accentOrange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppColors.backgroundSecondary,
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.textSecondary, size: 48),
          const SizedBox(height: 8),
          const Text('اضغط لإضافة صورة',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 4),
            child: Text(title,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: children),
          ),
        ],
      );
}

// ─── Toggle row ───────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ]),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
            inactiveThumbColor: AppColors.textSecondary,
          ),
        ]),
      );
}

// ─── Form field ───────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final int maxLines;
  final TextDirection textDirection;
  final IconData? suffixIcon;

  const _FormField({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.readOnly = false,
    this.maxLines = 1,
    this.textDirection = TextDirection.rtl,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Directionality(
                  textDirection: textDirection,
                  child: TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    readOnly: readOnly,
                    maxLines: maxLines,
                    style: TextStyle(
                      color: readOnly
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      suffixIcon: suffixIcon != null
                          ? Icon(suffixIcon,
                              color: AppColors.textSecondary, size: 18)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      );
}
