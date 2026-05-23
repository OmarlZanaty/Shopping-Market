import 'package:flutter/material.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _api = ApiService();
  List<AddressModel> _addresses = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final addrs = await _api.getAddresses();
      if (mounted) setState(() { _addresses = addrs; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('عناوين التوصيل', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.midnight),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.coral,
        label: const Text('إضافة عنوان', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        icon: const Icon(Icons.add_location_alt_outlined),
        onPressed: () {}),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
        : _addresses.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_off_outlined, size: 70, color: AppColors.sky),
              SizedBox(height: 16),
              Text('لا توجد عناوين محفوظة', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 15)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _addresses.length,
              itemBuilder: (_, i) {
                final addr = _addresses[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: addr.isDefault ? AppColors.sapphire : AppColors.border, width: addr.isDefault ? 2 : 1)),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.location_on_rounded, color: AppColors.sapphire)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(addr.label, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                        if (addr.isDefault) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(100)),
                          child: const Text('الافتراضي', style: TextStyle(color: AppColors.sapphire, fontSize: 10, fontFamily: 'Cairo')))],
                      ]),
                      const SizedBox(height: 3),
                      Text('${addr.fullAddress}\nعمارة ${addr.buildingNumber} - دور ${addr.floorNumber} - شقة ${addr.apartmentNumber}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFamily: 'Cairo')),
                    ])),
                    IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () async { await _api.deleteAddress(addr.id!); _load(); }),
                  ]),
                );
              }),
    );
  }
}
