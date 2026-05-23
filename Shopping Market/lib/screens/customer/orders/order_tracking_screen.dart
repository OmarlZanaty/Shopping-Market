import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});
  @override State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _api = ApiService();
  GoogleMapController? _mapController;
  WebSocketChannel? _ws;
  OrderModel? _order;
  LatLng? _driverPos;
  bool _loading = true;

  static const _steps = ['new', 'preparing', 'out_for_delivery', 'delivered'];

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _connectWS();
  }

  Future<void> _loadOrder() async {
    try {
      final order = await _api.getOrder(widget.orderId);
      if (mounted) setState(() { _order = order; _loading = false; });
      if (order.driverLat != null && order.driverLng != null) {
        setState(() => _driverPos = LatLng(order.driverLat!, order.driverLng!));
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _connectWS() {
    try {
      _ws = WebSocketChannel.connect(Uri.parse('${AppConfig.wsBaseUrl}/ws/order/${widget.orderId}/'));
      _ws!.stream.listen((msg) {
        final data = jsonDecode(msg as String) as Map<String, dynamic>;
        if (!mounted) return;
        if (data['type'] == 'driver_location') {
          final lat = double.tryParse(data['latitude'].toString());
          final lng = double.tryParse(data['longitude'].toString());
          if (lat != null && lng != null) {
            setState(() => _driverPos = LatLng(lat, lng));
            _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
          }
        } else if (data['type'] == 'order_update') {
          _loadOrder();
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() { _ws?.sink.close(); _mapController?.dispose(); super.dispose(); }

  int get _currentStep => _steps.indexOf(_order?.status ?? 'new');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تتبع الطلب #${widget.orderId}', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.midnight),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
        : Column(children: [
            // Map
            SizedBox(
              height: 280,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driverPos ?? LatLng(_order?.deliveryLat ?? 30.0, _order?.deliveryLng ?? 31.0),
                  zoom: 15,
                ),
                onMapCreated: (c) => _mapController = c,
                markers: {
                  if (_driverPos != null)
                    Marker(markerId: const MarkerId('driver'), position: _driverPos!,
                      infoWindow: const InfoWindow(title: 'المندوب'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)),
                  if (_order != null && _order!.deliveryLat != 0)
                    Marker(markerId: const MarkerId('customer'),
                      position: LatLng(_order!.deliveryLat, _order!.deliveryLng),
                      infoWindow: const InfoWindow(title: 'موقعك'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
                },
                myLocationEnabled: true,
                zoomControlsEnabled: false,
              ),
            ),

            // Status stepper
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
              // Status progress
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(children: List.generate(_steps.length, (i) {
                  final done = i <= _currentStep;
                  final current = i == _currentStep;
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(children: [
                      Container(width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: done ? AppColors.mint : AppColors.border,
                          shape: BoxShape.circle,
                          boxShadow: current ? [BoxShadow(color: AppColors.mint.withOpacity(0.4), blurRadius: 8)] : null,
                        ),
                        child: Icon(done ? Icons.check : OrderStatus.icon(_steps[i]), color: Colors.white, size: 14)),
                      if (i < _steps.length - 1)
                        Container(width: 2, height: 36, color: i < _currentStep ? AppColors.mint : AppColors.border),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(child: Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text(OrderStatus.labelAr(_steps[i]),
                        style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                          color: done ? AppColors.midnight : AppColors.textMuted, fontFamily: 'Cairo')))),
                  ]);
                }))),
              const SizedBox(height: 14),

              // Driver info
              if (_order?.driverName != null) Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(width: 48, height: 48, decoration: const BoxDecoration(color: AppColors.ice, shape: BoxShape.circle),
                    child: const Icon(Icons.delivery_dining_rounded, color: AppColors.sapphire, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_order!.driverName!, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                    if (_order?.driverRating != null) Row(children: [
                      const Icon(Icons.star_rounded, color: AppColors.gold, size: 14),
                      Text(' ${_order!.driverRating!.toStringAsFixed(1)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    ]),
                  ])),
                  if (_order?.driverPhone != null)
                    IconButton(
                      icon: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.phone_rounded, color: Colors.white, size: 20)),
                      onPressed: () {},
                    ),
                ])),
              const SizedBox(height: 14),

              // Confirm receipt button
              if (_order?.status == 'out_for_delivery')
                SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.mint, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () async {
                    final result = await _api.confirmReceipt(widget.orderId);
                    if (mounted) {
                      _loadOrder();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('تم التأكيد! +${result['points_earned']} نقطة ⭐', style: const TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: AppColors.mint, behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                    }
                  },
                  child: const Text('تأكيد استلام الطلب ✅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                )),
            ]))),
          ]),
    );
  }
}
