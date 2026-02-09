import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio/audio_player_mobile.dart';
import '../services/audio/audio_player_web.dart';
import '../services/audio/audio_service.dart';
import '../services/ws_service.dart';

class TranscriptEntry {
  final String role; // 'user' or 'ai'
  final String text;
  final String? emotion;

  const TranscriptEntry({
    required this.role,
    required this.text,
    this.emotion,
  });
}

class ChatState {
  final WsConnectionState connectionState;
  final List<TranscriptEntry> transcript;
  final String currentEmotion;
  final double valence;
  final double arousal;
  final String intensity;
  final bool aiSpeaking;
  final bool aiSearching;
  final String? searchTool;
  final String? error;

  const ChatState({
    this.connectionState = WsConnectionState.disconnected,
    this.transcript = const [],
    this.currentEmotion = 'neutral',
    this.valence = 0.0,
    this.arousal = 0.2,
    this.intensity = 'low',
    this.aiSpeaking = false,
    this.aiSearching = false,
    this.searchTool,
    this.error,
  });

  /// The emotion image key, e.g. "happy_mid", "angry_high".
  String get emotionKey => '${currentEmotion}_$intensity';

  ChatState copyWith({
    WsConnectionState? connectionState,
    List<TranscriptEntry>? transcript,
    String? currentEmotion,
    double? valence,
    double? arousal,
    String? intensity,
    bool? aiSpeaking,
    bool? aiSearching,
    String? searchTool,
    String? error,
  }) {
    return ChatState(
      connectionState: connectionState ?? this.connectionState,
      transcript: transcript ?? this.transcript,
      currentEmotion: currentEmotion ?? this.currentEmotion,
      valence: valence ?? this.valence,
      arousal: arousal ?? this.arousal,
      intensity: intensity ?? this.intensity,
      aiSpeaking: aiSpeaking ?? this.aiSpeaking,
      aiSearching: aiSearching ?? this.aiSearching,
      searchTool: searchTool ?? this.searchTool,
      error: error,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final WsService _ws = WsService();
  AudioPlayer? _player;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<WsConnectionState>? _stateSub;
  bool _playerInitialized = false;

  // Feature 2: Minimum 2s emotion display timing
  static const _minEmotionDisplayMs = 2000;
  DateTime _lastEmotionChangeTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingEmotionTimer;
  ({String emotion, double valence, double arousal, String intensity})? _queuedEmotion;

  ChatNotifier() : super(const ChatState()) {
    _initPlayer();
  }

  void _initPlayer() {
    if (kIsWeb) {
      _player = WebAudioPlayerImpl();
    } else {
      _player = MobileAudioPlayer();
    }
  }

  Future<void> connect({
    required String deviceId,
    required String characterId,
    String? displayName,
  }) async {
    _stateSub = _ws.stateStream.listen((wsState) {
      state = state.copyWith(connectionState: wsState);
    });

    _messageSub = _ws.messages.listen(_onMessage);

    await _ws.connect(
      deviceId: deviceId,
      characterId: characterId,
      displayName: displayName,
    );
  }

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String;
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'status':
        final action = payload['action'] as String? ?? '';
        final tool = payload['tool'] as String? ?? '';
        if (action == 'searching') {
          state = state.copyWith(
            aiSearching: true,
            searchTool: tool,
          );
        } else if (action == 'done') {
          state = state.copyWith(aiSearching: false);
        }

      case 'audio':
        if (!_playerInitialized) {
          _player?.init();
          _playerInitialized = true;
        }

        final audioB64 = payload['data'] as String;
        final audioBytes = base64Decode(audioB64);
        _player?.feed(Uint8List.fromList(audioBytes));

        // Don't update emotion from audio messages — audio chunks arrive
        // before text transcription, so they carry stale emotion data.
        // Emotion is updated only from 'text' messages after classification.
        state = state.copyWith(
          aiSpeaking: true,
          aiSearching: false,
        );

      case 'text':
        final text = payload['text'] as String? ?? '';
        final emotion = payload['emotion'] as String? ?? state.currentEmotion;
        final valence = (payload['valence'] as num?)?.toDouble() ?? state.valence;
        final arousal = (payload['arousal'] as num?)?.toDouble() ?? state.arousal;
        final intensity = payload['intensity'] as String? ?? state.intensity;
        if (text.isNotEmpty) {
          // Update transcript immediately (no gate)
          state = state.copyWith(
            transcript: [
              ...state.transcript,
              TranscriptEntry(role: 'ai', text: text, emotion: emotion),
            ],
            aiSearching: false,
          );
          // Feature 2: Timer-gated visual emotion update
          _updateEmotionIfReady(
            emotion: emotion,
            valence: valence,
            arousal: arousal,
            intensity: intensity,
          );
        }

      case 'turn_complete':
        state = state.copyWith(aiSpeaking: false);

      case 'interrupted':
        _player?.stop();
        state = state.copyWith(aiSpeaking: false);

      case 'error':
        final message = payload['message'] as String? ?? 'Unknown error';
        state = state.copyWith(error: message);
    }
  }

  /// Feature 2: Apply emotion update respecting minimum display time.
  void _updateEmotionIfReady({
    required String emotion,
    required double valence,
    required double arousal,
    required String intensity,
  }) {
    // Same emotion+intensity → just update valence/arousal (no visual change)
    if (emotion == state.currentEmotion && intensity == state.intensity) {
      state = state.copyWith(valence: valence, arousal: arousal);
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastEmotionChangeTime).inMilliseconds;

    if (elapsed >= _minEmotionDisplayMs) {
      // Enough time passed — apply immediately
      _applyEmotion(emotion: emotion, valence: valence, arousal: arousal, intensity: intensity);
    } else {
      // Too soon — queue the newest emotion and start a timer
      _pendingEmotionTimer?.cancel();
      _queuedEmotion = (emotion: emotion, valence: valence, arousal: arousal, intensity: intensity);
      final remaining = _minEmotionDisplayMs - elapsed;
      _pendingEmotionTimer = Timer(Duration(milliseconds: remaining), () {
        final queued = _queuedEmotion;
        if (queued != null) {
          _applyEmotion(
            emotion: queued.emotion,
            valence: queued.valence,
            arousal: queued.arousal,
            intensity: queued.intensity,
          );
          _queuedEmotion = null;
        }
      });
    }
  }

  void _applyEmotion({
    required String emotion,
    required double valence,
    required double arousal,
    required String intensity,
  }) {
    state = state.copyWith(
      currentEmotion: emotion,
      valence: valence,
      arousal: arousal,
      intensity: intensity,
    );
    _lastEmotionChangeTime = DateTime.now();
  }

  void sendText(String text) {
    _ws.sendText(text);
    state = state.copyWith(
      transcript: [
        ...state.transcript,
        TranscriptEntry(role: 'user', text: text),
      ],
    );
  }

  void sendAudio(Uint8List audioBytes) {
    _ws.sendAudio(audioBytes);
  }

  Future<void> disconnect() async {
    _pendingEmotionTimer?.cancel();
    _pendingEmotionTimer = null;
    _queuedEmotion = null;
    _player?.stop();
    await _ws.disconnect();
    await _messageSub?.cancel();
    await _stateSub?.cancel();
    _messageSub = null;
    _stateSub = null;
    _playerInitialized = false;
    state = const ChatState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _pendingEmotionTimer?.cancel();
    _player?.dispose();
    _ws.dispose();
    _messageSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.autoDispose<ChatNotifier, ChatState>(
  (ref) => ChatNotifier(),
);
