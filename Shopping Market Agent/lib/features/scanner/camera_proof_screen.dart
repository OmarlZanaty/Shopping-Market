import 'dart:io';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_envelope.dart';
import '../../core/network/dio_client.dart';

/// Full-screen camera capture for proof photography. On confirm:
///  1. Compresses to WebP, <1MB
///  2. Requests presigned URL from /uploads/presign/
///  3. Uploads to S3 via PUT
///  4. Pops with the final public URL
class CameraProofScreen extends StatefulWidget {
  const CameraProofScreen({super.key});
  @override
  State<CameraProofScreen> createState() => _CameraProofScreenState();
}

class _CameraProofScreenState extends State<CameraProofScreen> {
  CameraController? _ctrl;
  Future<void>? _initFuture;
  XFile? _captured;
  bool _uploading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _ctrl = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await _ctrl!.initialize();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    final file = await _ctrl!.takePicture();
    setState(() => _captured = file);
  }

  Future<void> _confirm() async {
    if (_captured == null) return;
    setState(() { _uploading = true; _progress = 0; });
    try {
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/proof_${DateTime.now().millisecondsSinceEpoch}.webp';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        _captured!.path, outPath, format: CompressFormat.webp, quality: 78, minWidth: 1280,
      );
      final filePath = compressed?.path ?? _captured!.path;
      final filename = filePath.split('/').last;

      // Presign
      final presign = await DioClient.I.dio.post(ApiConstants.uploadsPresign, data: {
        'filename': filename, 'content_type': 'image/webp', 'folder': 'agent_proofs',
      });
      final data = ApiEnvelope.unwrap(presign.data) ?? presign.data;
      final putUrl = data['url'] ?? data['put_url'];
      final publicUrl = data['public_url'] ?? data['file_url'] ?? putUrl;
      if (putUrl == null) throw 'فشل الحصول على رابط الرفع';

      // Upload to S3
      final bytes = await File(filePath).readAsBytes();
      await Dio().put(
        putUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {
          'Content-Type': 'image/webp',
          Headers.contentLengthHeader: bytes.length,
        }),
        onSendProgress: (sent, total) =>
            setState(() => _progress = total > 0 ? sent / total : 0),
      );

      if (!mounted) return;
      Navigator.of(context).pop(publicUrl.toString());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل الرفع: $e'),
        backgroundColor: AppColors.errorRed,
      ));
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done || _ctrl == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accentOrange));
          }
          if (_captured != null) return _reviewView();
          return Stack(children: [
            Positioned.fill(child: CameraPreview(_ctrl!)),
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _shoot,
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: const Icon(Icons.camera, color: Colors.white, size: 36),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _reviewView() => Stack(children: [
        Positioned.fill(child: Image.file(File(_captured!.path), fit: BoxFit.contain)),
        if (_uploading)
          Container(
            color: Colors.black.withOpacity(0.6),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 64, height: 64,
                  child: CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    color: AppColors.accentOrange, strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 12),
                Text('${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              ]),
            ),
          ),
        Positioned(
          bottom: 32, left: 16, right: 16,
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _uploading ? null : () => setState(() => _captured = null),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('إعادة التصوير', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _uploading ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('استخدام الصورة'),
              ),
            ),
          ]),
        ),
      ]);
}
