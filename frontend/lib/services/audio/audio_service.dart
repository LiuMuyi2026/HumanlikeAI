import 'dart:typed_data';

/// Abstract audio recorder interface
abstract class AudioRecorder {
  Future<bool> start();
  Future<void> stop();
  bool get isRecording;

  /// Returns PCM audio chunks as a list of [Uint8List].
  /// Each call drains the buffer.
  List<Uint8List> drainChunks();
}

/// Abstract audio player interface for PCM playback
abstract class AudioPlayer {
  void init();
  void feed(Uint8List pcmData);
  void stop();
  void dispose();
}
