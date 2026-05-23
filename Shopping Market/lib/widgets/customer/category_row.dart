import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

class CategoryRow extends StatelessWidget {
  final List<CategoryModel> categories;
  final int selectedId;
  final void Function(int) onSelect;
  const CategoryRow({super.key, required this.categories, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final all = [CategoryModel(id: 0, nameAr: 'الكل', nameEn: 'All', icon: '🛒'), ...categories];
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: all.length,
        itemBuilder: (_, i) {
          final cat = all[i];
          final selected = selectedId == cat.id;
          return GestureDetector(
            onTap: () => onSelect(cat.id),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              child: Column(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.midnight : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.midnight : AppColors.border, width: 1.5),
                    boxShadow: selected ? [BoxShadow(color: AppColors.midnight.withOpacity(0.15), blurRadius: 8, offset: const Offset(0,3))] : null,
                  ),
                  child: Center(child: Text(cat.icon, style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(height: 5),
                Text(cat.nameAr, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: selected ? AppColors.midnight : AppColors.textMuted, fontFamily: 'Cairo')),
              ]),
            ),
          );
        },
      ),
    );
  }
}
