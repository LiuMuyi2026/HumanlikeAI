import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/audio_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/ws_service.dart';
import '../../widgets/avatar_circle.dart';
import '../../widgets/emotion_avatar.dart';
import '../../widgets/waveform_indicator.dart';
import '../../widgets/camera_preview.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String characterId;
  final String mode; // 'voice' or 'video'

  const CallScreen({
    super.key,
    required this.characterId,
    this.mode = 'voice',
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  bool _connected = false;

  bool get _isVideoMode => widget.mode == 'video';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _startCall();
  }

  Future<void> _startCall() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final user = await ref.read(userProvider.future);

    ref.read(chatProvider.notifier).connect(
      deviceId: deviceId,
      characterId: widget.characterId,
      displayName: user?.displayName,
    );
  }

  void _onConnected() {
    if (_connected) return;
    _connected = true;
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
    // Auto-start recording
    ref.read(audioProvider.notifier).startRecording();
  }

  Future<void> _endCall() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    await ref.read(audioProvider.notifier).stopRecording();
    await ref.read(chatProvider.notifier).disconnect();
    // Feature 4: Delayed invalidation so next fetch picks up relationship changes
    final charId = widget.characterId;
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) ref.invalidate(characterDetailProvider(charId));
    });
    if (mounted) context.pop();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final audioState = ref.watch(audioProvider);
    final characterAsync =
        ref.watch(characterDetailProvider(widget.characterId));

    // Track connection state
    if (chatState.connectionState == WsConnectionState.connected) {
      _onConnected();
    }

    // Show errors
    ref.listen<ChatState>(chatProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red.shade700,
          ),
        );
        ref.read(chatProvider.notifier).clearError();
      }
    });

    final character = characterAsync.valueOrNull;
    final characterName = character?.name ?? 'HLAI';
    final isConnected =
        chatState.connectionState == WsConnectionState.connected;
    final isConnecting = chatState.connectionState ==
            WsConnectionState.connecting ||
        chatState.connectionState == WsConnectionState.authenticating;

    // Check if we have an emotion pack for video mode
    final packAsync =
        ref.watch(emotionPackStatusProvider(widget.characterId));
    final hasEmotionPack = packAsync.valueOrNull?.hasAny ?? false;
    final useVideoEmotionMode = _isVideoMode && hasEmotionPack && isConnected;

    return Scaffold(
      body: useVideoEmotionMode
          ? _buildVideoEmotionLayout(
              chatState, audioState, characterName, isConnected, isConnecting)
          : _buildVoiceLayout(
              chatState, audioState, characterName, isConnected,
              isConnecting, hasEmotionPack),
    );
  }

  /// Video mode with emotion pack: full-screen emotion image as background.
  Widget _buildVideoEmotionLayout(
    ChatState chatState,
    AudioState audioState,
    String characterName,
    bool isConnected,
    bool isConnecting,
  ) {
    final api = ref.watch(apiClientProvider);
    final emotionKey = chatState.emotionKey;
    final imageUrl = api.emotionImageUrl(widget.characterId, emotionKey);

    // Pre-cache next emotion image so transition is seamless
    precacheImage(NetworkImage(imageUrl), context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen emotion image — gaplessPlayback keeps old image until new one loads
        Image.network(
          imageUrl,
          key: ValueKey('emotion_$emotionKey'),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            decoration:
                const BoxDecoration(gradient: AppTheme.backgroundGradient),
          ),
        ),

        // Subtle breathing animation overlay when speaking
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final opacity = chatState.aiSpeaking
                ? 0.05 + (_pulseController.value * 0.05)
                : 0.0;
            return Container(
              color: Colors.white.withValues(alpha: opacity),
            );
          },
        ),

        // Gradient overlays for readability
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 140,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // UI overlay
        SafeArea(
          child: Column(
            children: [
              // Top bar
              _buildTopBar(isConnected, isConnecting, characterName),

              const Spacer(),

              // Emotion label + waveform
              _buildEmotionLabel(chatState),
              const SizedBox(height: 8),
              if (chatState.aiSearching) _buildSearchingIndicator(chatState),
              const SizedBox(height: 8),
              if (isConnected)
                WaveformIndicator(
                  active: chatState.aiSpeaking,
                  color: Colors.white,
                ),

              const SizedBox(height: 16),

              // Transcript
              if (chatState.transcript.isNotEmpty) _buildTranscript(chatState),

              const SizedBox(height: 8),

              // Controls
              _buildControls(audioState),
            ],
          ),
        ),

        // Camera PIP
        Positioned(
          top: 80,
          right: 16,
          child: CameraPreviewWidget(
            width: 100,
            height: 140,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  /// Voice mode (or video without emotion pack): centered avatar layout.
  Widget _buildVoiceLayout(
    ChatState chatState,
    AudioState audioState,
    String characterName,
    bool isConnected,
    bool isConnecting,
    bool hasEmotionPack,
  ) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top bar
                _buildTopBar(isConnected, isConnecting, characterName),

                const Spacer(flex: 1),

                // Avatar area with emotion images
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = chatState.aiSpeaking
                        ? 1.0 + (_pulseController.value * 0.05)
                        : 1.0;
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Column(
                    children: [
                      if (isConnected)
                        EmotionAvatar(
                          characterId: widget.characterId,
                          size: 200,
                          hasEmotionPack: hasEmotionPack,
                        )
                      else
                        AvatarCircle(
                          characterId: widget.characterId,
                          radius: 70,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        characterName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Searching indicator
                if (chatState.aiSearching) _buildSearchingIndicator(chatState),

                const SizedBox(height: 8),

                // Waveform
                if (isConnected)
                  WaveformIndicator(
                    active: chatState.aiSpeaking,
                    color: AppTheme.primary,
                  ),

                const Spacer(flex: 1),

                // Transcript
                if (chatState.transcript.isNotEmpty) _buildTranscript(chatState),

                const Spacer(flex: 1),

                // Controls
                _buildControls(audioState),
              ],
            ),

            // Camera PIP overlay (video mode only)
            if (_isVideoMode)
              Positioned(
                top: 80,
                right: 16,
                child: CameraPreviewWidget(
                  width: 120,
                  height: 160,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Shared widgets ---

  Widget _buildTopBar(bool isConnected, bool isConnecting, String characterName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _endCall,
          ),
          const Spacer(),
          Icon(
            _isVideoMode ? Icons.videocam : Icons.call,
            color: Colors.white.withValues(alpha: 0.6),
            size: 18,
          ),
          const SizedBox(width: 8),
          if (isConnected)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_callDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            )
          else if (isConnecting)
            Text(
              'Connecting...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildEmotionLabel(ChatState chatState) {
    final emotion = chatState.currentEmotion;
    final (color, label) = _emotionData(emotion);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  static (Color, String) _emotionData(String emotion) {
    return switch (emotion) {
      'happy' => (Colors.amber, 'Happy'),
      'sad' => (Colors.blue, 'Sad'),
      'angry' => (Colors.red, 'Angry'),
      'excited' => (Colors.orange, 'Excited'),
      'thinking' => (AppTheme.primary, 'Thinking'),
      'surprised' => (Colors.purple, 'Surprised'),
      'loving' => (AppTheme.accent, 'Loving'),
      'anxious' => (Colors.teal, 'Anxious'),
      'jealous' => (Colors.deepOrange, 'Jealous'),
      'shy' => (Colors.pink, 'Shy'),
      'disappointed' => (Colors.blueGrey, 'Disappointed'),
      'frustrated' => (const Color(0xFFE65100), 'Frustrated'),
      'proud' => (const Color(0xFFFFD600), 'Proud'),
      'grateful' => (Colors.green, 'Grateful'),
      'bored' => (Colors.grey, 'Bored'),
      'curious' => (Colors.lightBlue, 'Curious'),
      'embarrassed' => (Colors.pink[400]!, 'Embarrassed'),
      'playful' => (Colors.purple[400]!, 'Playful'),
      'lonely' => (Colors.indigo, 'Lonely'),
      'confused' => (Colors.brown, 'Confused'),
      _ => (Colors.grey, 'Neutral'),
    };
  }

  Widget _buildSearchingIndicator(ChatState chatState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          chatState.searchTool == 'recall_memory'
              ? 'Recalling...'
              : 'Searching...',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscript(ChatState chatState) {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: chatState.transcript.length,
        itemBuilder: (context, index) {
          final entry = chatState.transcript[
              chatState.transcript.length - 1 - index];
          final isUser = entry.role == 'user';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppTheme.primary.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      entry.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(AudioState audioState) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: audioState.isRecording ? Icons.mic : Icons.mic_off,
            label: audioState.isRecording ? 'Mute' : 'Unmute',
            isActive: audioState.isRecording,
            onTap: () => ref.read(audioProvider.notifier).toggleRecording(),
          ),
          GestureDetector(
            onTap: _endCall,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
              child: const Icon(
                Icons.call_end,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          _buildControlButton(
            icon: Icons.volume_up,
            label: 'Speaker',
            isActive: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.white54,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
