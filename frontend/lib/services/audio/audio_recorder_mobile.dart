import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart' as rec;

import 'audio_service.dart';

class MobileAudioRecorder implements AudioRecorder {
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  StreamSubscription<rec.RecordState>? _stateSub;
  StreamSubscription<Uint8List>? _dataSub;
  final List<Uint8List> _buffer = [];
  bool _recording = false;

  @override
  Future<bool> start() async {
    if (_recording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    final stream = await _recorder.startStream(
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
    );

    _dataSub = stream.listen((data) {
      _buffer.add(data);
    });

    _recording = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_recording) return;
    _recording = false;
    await _dataSub?.cancel();
    _dataSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _recorder.stop();
  }

  @override
  bool get isRecording => _recording;

  @override
  List<Uint8List> drainChunks() {
    final chunks = List<Uint8List>.from(_buffer);
    _buffer.clear();
    return chunks;
  }
}
