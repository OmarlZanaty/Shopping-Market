import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../utils/constants.dart';

/// Full-screen map picker. Navigates back with [LatLng] when the user taps
/// "تأكيد الموقع". Returns null if dismissed without confirmation.
class MapLocationPickerScreen extends StatefulWidget {
  /// Optional starting position. If null, the device GPS is used.
  final LatLng? initialPosition;

  const MapLocationPickerScreen({super.key, this.initialPosition});

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final Completer<GoogleMapController> _ctrl = Completer();

  LatLng _center = const LatLng(30.0444, 31.2357); // Cairo fallback
  bool _locating = true;
  bool _reverseGeocoding = false;
  String? _addressHint;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _center = widget.initialPosition!;
      _locating = false;
      _reverseGeocode(_center);
    } else {
      _goToCurrentLocation();
    }
  }

  // ── Location permission + move camera ─────────────────────────────────────

  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      // Check / request permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        // Fall back to Cairo if permission refused
        setState(() => _locating = false);
        _reverseGeocode(_center);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _center = ll;
        _locating = false;
      });
      final mapCtrl = await _ctrl.future;
      mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(ll, 16));
      _reverseGeocode(ll);
    } catch (e) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _reverseGeocode(LatLng ll) async {
    setState(() => _reverseGeocoding = true);
    try {
      final marks = await placemarkFromCoordinates(ll.latitude, ll.longitude);
      if (!mounted) return;
      final m = marks.first;
      final parts = [
        m.street,
        m.subLocality,
        m.locality,
        m.administrativeArea,
      ].where((p) => p != null && p.isNotEmpty).toList();
      setState(() {
        _addressHint = parts.join('، ');
        _reverseGeocoding = false;
      });
    } catch (_) {
      if (mounted) setState(() => _reverseGeocoding = false);
    }
  }

  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
  }

  void _onCameraIdle() {
    _reverseGeocode(_center);
  }

  void _confirm() {
    // Enforce the delivery radius: block confirmation if the picked point is
    // farther from the store than the admin-configured limit.
    final meters = Geolocator.distanceBetween(
      DeliveryConfig.storeLat, DeliveryConfig.storeLng,
      _center.latitude, _center.longitude,
    );
    final km = meters / 1000;
    if (km > DeliveryConfig.radiusKm) {
      _showOutOfRangeDialog(km);
      return;
    }
    Navigator.of(context).pop(_center);
  }

  void _showOutOfRangeDialog(double km) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.location_off_rounded, color: AppColors.coral),
          SizedBox(width: 10),
          Text('خارج نطاق التوصيل',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 17,
              )),
        ]),
        content: Text(
          'عذراً، هذا الموقع يبعد حوالي ${km.toStringAsFixed(1)} كم عن المتجر، '
          'ونحن نوصّل حتى ${DeliveryConfig.radiusKm.toStringAsFixed(DeliveryConfig.radiusKm.truncateToDouble() == DeliveryConfig.radiusKm ? 0 : 1)} كم فقط.\n'
          'يرجى اختيار موقع أقرب لإتمام الطلب. 🙏',
          style: const TextStyle(
              fontFamily: 'Cairo', color: AppColors.textMuted, height: 1.6),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.midnight,
        title: const Text(
          'تحديد الموقع على الخريطة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (_locating)
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Google Map ──────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 15),
            onMapCreated: (c) => _ctrl.complete(c),
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Fixed center pin ─────────────────────────────────────────────
          const Center(
            child: Padding(
              // Pin sits slightly above the visual center so the tip aligns
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.location_pin,
                size: 52,
                color: AppColors.coral,
              ),
            ),
          ),

          // ── Address hint bar ─────────────────────────────────────────────
          Positioned(
            top: 12, left: 16, right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined,
                      color: AppColors.coral, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _reverseGeocoding
                        ? const LinearProgressIndicator(
                            color: AppColors.coral, minHeight: 2)
                        : Text(
                            _addressHint ?? 'اسحب الخريطة لتحديد الموقع',
                            style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ]),
              ),
            ),
          ),

          // ── My location button ───────────────────────────────────────────
          Positioned(
            bottom: 108, right: 16,
            child: FloatingActionButton.small(
              heroTag: 'myLoc',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.sapphire,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),

          // ── Confirm button ───────────────────────────────────────────────
          Positioned(
            bottom: 32, left: 20, right: 20,
            child: SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'تأكيد الموقع ✅',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
