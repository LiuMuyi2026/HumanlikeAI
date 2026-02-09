import 'dart:js_interop';

@JS('cameraPreview.start')
external JSPromise<JSBoolean> _cameraStart(JSString elementId);

@JS('cameraPreview.stop')
external void _cameraStop();

class CameraService {
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
}
