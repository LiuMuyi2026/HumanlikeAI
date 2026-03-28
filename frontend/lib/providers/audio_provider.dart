import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio/audio_recorder_mobile.dart';
import '../services/audio/audio_recorder_web.dart';
import '../services/audio/audio_service.dart';
import 'chat_provider.dart';

class AudioState {
  final bool isRecording;

  const AudioState({this.isRecording = false});
}

class AudioNotifier extends StateNotifier<AudioState> {
  final Ref _ref;
  AudioRecorder? _recorder;
  Timer? _pollTimer;

  AudioNotifier(this._ref) : super(const AudioState()) {
    _initRecorder();
  }

  void _initRecorder() {
    if (kIsWeb) {
      _recorder = WebAudioRecorderImpl();
    } else {
      _recorder = MobileAudioRecorder();
    }
  }

  Future<void> startRecording() async {
    if (state.isRecording) return;

    final started = await _recorder!.start();
    if (!started) return;

    state = const AudioState(isRecording: true);

    // Poll for audio chunks every 100ms
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _drainAndSend();
    });
  }

  void _drainAndSend() {
    if (!state.isRecording) return;

    final chunks = _recorder!.drainChunks();
    final chatNotifier = _ref.read(chatProvider.notifier);

    for (final chunk in chunks) {
      chatNotifier.sendAudio(Uint8List.fromList(chunk));
    }
  }

  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    _pollTimer?.cancel();
    _pollTimer = null;

    // Drain remaining chunks
    _drainAndSend();

    await _recorder!.stop();
    state = const AudioState(isRecording: false);
  }

  Future<void> toggleRecording() async {
    if (state.isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (state.isRecording) {
      _recorder?.stop();
    }
    super.dispose();
  }
}

final audioProvider =
    StateNotifierProvider.autoDispose<AudioNotifier, AudioState>(
  (ref) => AudioNotifier(ref),
);
