import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/models.dart';
import '../../../utils/constants.dart';

/// Full-screen grid of all categories.
/// Pops with the selected [CategoryModel.id] (or null if nothing chosen).
class AllCategoriesScreen extends StatefulWidget {
  final List<CategoryModel> categories;
  final int selectedId;

  const AllCategoriesScreen({
    super.key,
    required this.categories,
    required this.selectedId,
  });

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
  late int _selectedId;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CategoryModel> get _all => [
        const CategoryModel(id: 0, nameAr: 'الكل', nameEn: 'All', icon: '🛒'),
        ...widget.categories,
      ];

  List<CategoryModel> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where((c) =>
            c.nameAr.contains(q) ||
            c.nameEn.toLowerCase().contains(q))
        .toList();
  }

  void _select(CategoryModel cat) {
    setState(() => _selectedId = cat.id);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) Navigator.pop(context, cat.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── AppBar with search ───────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.midnight,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'جميع الأقسام',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'ابحث في الأقسام...',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white54, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white54, size: 18))
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
            ),
          ),

          // ── Count chip ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.coral.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${filtered.length} قسم',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.coral,
                    ),
                  ),
                ),
              ]),
            ),
          ),

          // ── Categories grid ──────────────────────────────────────────────
          if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                          color: AppColors.ice,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.category_outlined,
                          color: AppColors.coral, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text('لا توجد أقسام',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                          color: AppColors.textMain,
                        )),
                    const SizedBox(height: 6),
                    Text('لم نجد قسماً يطابق "$_query"',
                        style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Cairo',
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final cat = filtered[i];
                    return _CategoryCard(
                      category: cat,
                      selected: cat.id == _selectedId,
                      onTap: () => _select(cat),
                    );
                  },
                  childCount: filtered.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Category Card
// ══════════════════════════════════════════════════════════════════════════════
class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cat = category;
    final hasImage = (cat.imageUrl ?? '').isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.midnight : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.coral : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.coral.withOpacity(0.28)
                  : Colors.black.withOpacity(0.06),
              blurRadius: selected ? 18 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Image / emoji
            Expanded(
              flex: 60,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(17)),
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: cat.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => _fallback(selected),
                        errorWidget: (_, __, ___) => _fallback(selected),
                      )
                    : _fallback(selected),
              ),
            ),

            // Name
            Expanded(
              flex: 40,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      cat.nameAr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo',
                        color: selected
                            ? Colors.white
                            : AppColors.textMain,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (cat.productCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${cat.productCount} منتج',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Cairo',
                          color: selected
                              ? Colors.white54
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(bool sel) => Container(
        color: sel
            ? AppColors.coral.withOpacity(0.15)
            : AppColors.coral.withOpacity(0.06),
        child: Center(
          child:
              Text(category.icon, style: const TextStyle(fontSize: 34)),
        ),
      );
}
