import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'audio_service.dart';

@JS('recorderStart')
external JSPromise<JSBoolean> _recorderStart();

@JS('recorderStop')
external void _recorderStop();

@JS('recorderDrainChunks')
external JSString _recorderDrainChunks();

@JS('recorderIsRecording')
external JSBoolean _recorderIsRecording();

class WebAudioRecorderImpl implements AudioRecorder {
  @override
  Future<bool> start() async {
    try {
      final result = await _recorderStart().toDart;
      return result.toDart;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      _recorderStop();
    } catch (_) {}
  }

  @override
  bool get isRecording {
    try {
      return _recorderIsRecording().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  List<Uint8List> drainChunks() {
    try {
      final json = _recorderDrainChunks().toDart;
      if (json == '[]') return [];
      final chunks = (jsonDecode(json) as List).cast<String>();
      return chunks.map((b64) => base64Decode(b64)).toList();
    } catch (_) {
      return [];
    }
  }
}
