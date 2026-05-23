import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class SearchBarWidget extends StatelessWidget {
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final void Function(String)? onChanged;
  final bool autofocus;
  const SearchBarWidget({super.key, this.onTap, this.controller, this.onChanged, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.sky.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: AppColors.sky, size: 18),
          const SizedBox(width: 8),
          if (controller != null)
            Expanded(child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
              decoration: const InputDecoration.collapsed(
                hintText: 'ابحث عن منتج أو امسح الباركود...',
                hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 13),
              ),
            ))
          else
            Text('ابحث عن منتج أو امسح الباركود...',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontFamily: 'Cairo')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(8)),
            child: const Text('📷 مسح', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
          ),
        ]),
      ),
    );
  }
}
