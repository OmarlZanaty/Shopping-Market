import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class LocationService extends ChangeNotifier {
  final _api = ApiService();
  Timer? _timer;
  Position? _lastPosition;
  bool _isTracking = false;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<void> startTracking() async {
    final ok = await requestPermission();
    if (!ok) return;
    _isTracking = true;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _lastPosition = pos;
        await _api.updateLocation(pos.latitude, pos.longitude);
        notifyListeners();
      } catch (_) {}
    });
  }

  void stopTracking() {
    _timer?.cancel();
    _isTracking = false;
    notifyListeners();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}
