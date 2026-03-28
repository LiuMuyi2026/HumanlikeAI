import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'audio_service.dart';

@JS('pcmInit')
external void _pcmPlayerInit();

@JS('pcmFeed')
external void _pcmPlayerFeed(JSString base64Data);

@JS('pcmStop')
external void _pcmPlayerStop();

class WebAudioPlayerImpl implements AudioPlayer {
  @override
  void init() {
    try {
      _pcmPlayerInit();
    } catch (_) {}
  }

  @override
  void feed(Uint8List pcmData) {
    try {
      final b64 = base64Encode(pcmData);
      _pcmPlayerFeed(b64.toJS);
    } catch (_) {}
  }

  @override
  void stop() {
    try {
      _pcmPlayerStop();
    } catch (_) {}
  }

  @override
  void dispose() {
    stop();
  }
}
