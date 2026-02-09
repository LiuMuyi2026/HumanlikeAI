import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart' as ja;

import 'audio_service.dart';

/// A StreamAudioSource that we can push PCM data into.
class _PcmStreamSource extends ja.StreamAudioSource {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<int> _allBytes = [];

  void addPcm(Uint8List data) {
    // Wrap raw PCM in a minimal WAV header for just_audio
    _allBytes.addAll(data);
    _controller.add(data);
  }

  void reset() {
    _allBytes.clear();
  }

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    // Return all buffered PCM data as a WAV stream
    final wavHeader = _buildWavHeader(_allBytes.length, 24000, 1, 16);
    final allData = Uint8List.fromList([...wavHeader, ..._allBytes]);

    final effectiveEnd = end ?? allData.length;
    final subData = allData.sublist(start, effectiveEnd);

    return ja.StreamAudioResponse(
      sourceLength: allData.length,
      contentLength: subData.length,
      offset: start,
      stream: Stream.value(subData),
      contentType: 'audio/wav',
    );
  }

  static Uint8List _buildWavHeader(
    int dataLength,
    int sampleRate,
    int channels,
    int bitsPerSample,
  ) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final header = ByteData(44);

    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, 36 + dataLength, Endian.little);
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataLength, Endian.little);

    return header.buffer.asUint8List();
  }
}

class MobileAudioPlayer implements AudioPlayer {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  _PcmStreamSource? _source;

  @override
  void init() {
    _source = _PcmStreamSource();
  }

  @override
  void feed(Uint8List pcmData) {
    _source?.addPcm(pcmData);
    // Try to start playing if not already
    if (!_player.playing) {
      _player.setAudioSource(_source!).then((_) {
        _player.play();
      }).catchError((_) {});
    }
  }

  @override
  void stop() {
    _player.stop();
    _source?.reset();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
