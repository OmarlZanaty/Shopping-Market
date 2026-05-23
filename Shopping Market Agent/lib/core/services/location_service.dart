import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/api_constants.dart';
import '../network/dio_client.dart';

/// Driver-only continuous location streamer.
/// - Requests "while in use" permission first, then "always" if user agrees.
/// - Streams every 5s, throttles to 15s when the device hasn't moved > 10m.
/// - POSTs to /auth/location/.
class AgentLocationService {
  AgentLocationService._();
  static final AgentLocationService I = AgentLocationService._();

  StreamSubscription<Position>? _sub;
  Position? _lastSent;
  DateTime? _lastSendAt;

  bool get isRunning => _sub != null;

  Future<bool> requestPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<void> start() async {
    if (_sub != null) return;
    final ok = await requestPermission();
    if (!ok) {
      debugPrint('[Agent Location] permission denied');
      return;
    }
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (e) => debugPrint('[Agent Location] stream error: $e'),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _lastSent = null;
  }

  Future<void> _onPosition(Position p) async {
    // Throttle to 5s minimum, 15s if no movement > 10m.
    final now = DateTime.now();
    final movedFar = _lastSent == null ||
        Geolocator.distanceBetween(
                _lastSent!.latitude, _lastSent!.longitude, p.latitude, p.longitude) >
            10;
    final minInterval = movedFar ? const Duration(seconds: 5) : const Duration(seconds: 15);
    if (_lastSendAt != null && now.difference(_lastSendAt!) < minInterval) return;

    try {
      await DioClient.I.dio.post(ApiConstants.location, data: {
        'latitude': p.latitude, 'longitude': p.longitude, 'accuracy': p.accuracy,
      });
      _lastSent = p;
      _lastSendAt = now;
    } catch (e) {
      debugPrint('[Agent Location] send failed: $e');
    }
  }
}
