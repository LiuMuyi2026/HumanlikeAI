import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../config/theme.dart';
import '../services/camera_service.dart';

class CameraPreviewWidget extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const CameraPreviewWidget({
    super.key,
    this.width = 120,
    this.height = 160,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  static const _viewType = 'camera-preview-view';
  static bool _factoryRegistered = false;
  bool _started = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();

    // Register the platform view factory only once across all instances
    if (!_factoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final video =
            web.document.createElement('video') as web.HTMLVideoElement;
        video.id = 'camera-video';
        video.autoplay = true;
        video.muted = true;
        video.setAttribute('playsinline', '');
        video.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'cover'
          ..transform = 'scaleX(-1)';

        // Pass the element directly to JS so the stream can be attached
        // without relying on getElementById (fails in Flutter's shadow DOM).
        CameraService.setVideoElement(video);

        return video;
      });
      _factoryRegistered = true;
    }

    // Delay camera init until after the platform view is rendered in the DOM
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initCamera();
    });
  }

  Future<void> _initCamera() async {
    final ok = await CameraService.start();
    if (mounted) {
      setState(() {
        _started = ok;
        _failed = !ok;
      });
    }
  }

  @override
  void dispose() {
    CameraService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
        child: _failed
            ? const Center(
                child: Icon(Icons.videocam_off, color: Colors.white54, size: 32),
              )
            : !_started
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                  )
                : const HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
