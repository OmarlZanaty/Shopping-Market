import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

/// Bottom-sheet that lets the customer enter how many GRAMS they want of a
/// weight-based product. Returns the chosen amount in KILOGRAMS (e.g. 500 g →
/// 0.5), or null if cancelled. [initialKg] pre-fills the field when editing an
/// item already in the cart.
Future<double?> showWeightPicker(
  BuildContext context,
  ProductModel product, {
  double initialKg = 0.5,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _WeightPickerSheet(product: product, initialKg: initialKg),
  );
}

class _WeightPickerSheet extends StatefulWidget {
  final ProductModel product;
  final double initialKg;
  const _WeightPickerSheet({required this.product, required this.initialKg});

  @override
  State<_WeightPickerSheet> createState() => _WeightPickerSheetState();
}

class _WeightPickerSheetState extends State<_WeightPickerSheet> {
  late final TextEditingController _ctrl;
  int _grams = 500;

  // Quick-pick presets (grams).
  static const _presets = [250, 500, 1000, 1500, 2000];

  @override
  void initState() {
    super.initState();
    _grams = (widget.initialKg * 1000).round().clamp(50, 100000);
    _ctrl = TextEditingController(text: _grams.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setGrams(int g) {
    setState(() => _grams = g);
    _ctrl.text = g.toString();
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  double get _pricePerKg => widget.product.currentPrice;
  double get _lineTotal => _pricePerKg * (_grams / 1000);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Grabber
        Container(
          width: 42, height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.product.nameAr,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.midnight,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cairo',
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_pricePerKg.toStringAsFixed(2)} ج / كجم',
          style: const TextStyle(
            color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 12),
        ),
        const SizedBox(height: 18),

        // Grams input
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                fontFamily: 'Cairo', color: AppColors.midnight),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.ice,
                hintText: '500',
                suffixText: 'جرام',
                suffixStyle: const TextStyle(
                  fontFamily: 'Cairo', color: AppColors.textMuted,
                  fontWeight: FontWeight.w700),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (v) => setState(() => _grams = int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 10),
          _stepBtn(Icons.remove_rounded,
              () => _setGrams((_grams - 50).clamp(50, 100000))),
          const SizedBox(width: 6),
          _stepBtn(Icons.add_rounded,
              () => _setGrams((_grams + 50).clamp(50, 100000))),
        ]),
        const SizedBox(height: 14),

        // Presets
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _presets.map((g) {
            final active = g == _grams;
            return GestureDetector(
              onTap: () => _setGrams(g),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.coral : AppColors.ice,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: active ? AppColors.coral : AppColors.border),
                ),
                child: Text(
                  g < 1000 ? '$g جم' : '${(g / 1000).toStringAsFixed(g % 1000 == 0 ? 0 : 1)} كجم',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: active ? Colors.white : AppColors.textMain,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Confirm
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _grams >= 50
                ? () => Navigator.pop(context, _grams / 1000)
                : null,
            child: Text(
              'إضافة · ${_lineTotal.toStringAsFixed(2)} ج',
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColors.ice,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.midnight, size: 22),
        ),
      );
}
