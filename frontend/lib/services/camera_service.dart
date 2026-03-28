import 'dart:js_interop';

@JS('cameraPreview.setVideoElement')
external void _cameraSetVideoElement(JSObject element);

@JS('cameraPreview.start')
external JSPromise<JSBoolean> _cameraStart(JSString elementId);

@JS('cameraPreview.stop')
external void _cameraStop();

@JS('cameraPreview.captureFrame')
external JSString? _cameraCaptureFrame(JSNumber quality);

class CameraService {
  /// Store the video element reference so JS can attach the stream to it
  /// without needing getElementById (which fails in Flutter's shadow DOM).
  static void setVideoElement(JSObject element) {
    try {
      _cameraSetVideoElement(element);
    } catch (_) {}
  }

  static Future<bool> start({String elementId = 'camera-video'}) async {
    try {
      final result = await _cameraStart(elementId.toJS).toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  static void stop() {
    try {
      _cameraStop();
    } catch (_) {}
  }

  /// Capture current camera frame as base64 JPEG string.
  /// Returns null if camera is not running or capture fails.
  static String? captureFrame({double quality = 0.7}) {
    try {
      final result = _cameraCaptureFrame(quality.toJS);
      return result?.toDart;
    } catch (_) {
      return null;
    }
  }
}
