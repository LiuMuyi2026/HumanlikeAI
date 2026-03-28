import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/responsive.dart';
import '../../config/theme.dart';
import '../../providers/audio_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/ws_service.dart';
import '../../widgets/avatar_circle.dart';
import '../../widgets/waveform_indicator.dart';
import '../../services/camera_service.dart';
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
  Timer? _frameCaptureTimer;
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
      mode: widget.mode,
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

    // Start sending camera frames in video mode
    if (_isVideoMode) {
      _startFrameCapture();
    }
  }

  void _startFrameCapture() {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_connected) return;
      final frame = CameraService.captureFrame(quality: 0.6);
      if (frame != null) {
        ref.read(chatProvider.notifier).sendVideoFrame(frame);
      }
    });
  }

  Future<void> _endCall() async {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
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
    _frameCaptureTimer?.cancel();
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
      body: Stack(
        children: [
          // Main layout
          useVideoEmotionMode
              ? _buildVideoEmotionLayout(
                  chatState, audioState, characterName, isConnected, isConnecting)
              : _buildVoiceLayout(
                  chatState, audioState, characterName, isConnected,
                  isConnecting, hasEmotionPack),
          // Single camera PIP — persists across layout switches
          if (_isVideoMode)
            Positioned(
              top: 80,
              right: 16,
              child: CameraPreviewWidget(
                width: Responsive.value<double>(context, phone: 100, tablet: 130, desktop: 160),
                height: Responsive.value<double>(context, phone: 140, tablet: 180, desktop: 220),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
        ],
      ),
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

              // Waveform
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
            LayoutBuilder(
              builder: (context, constraints) {
                // Fixed elements: topBar(~64) + spacing(8+8) + waveform(40) + controls(~120) ≈ 240
                final fixedHeight = 240.0;
                final flexibleHeight = (constraints.maxHeight - fixedHeight).clamp(100.0, 800.0);
                // Avatar gets ~60% of flexible space, transcript gets ~25%
                final maxAvatarSize = Responsive.value<double>(context, phone: 200, tablet: 260, desktop: 300);
                final avatarSize = (flexibleHeight * 0.55).clamp(100.0, maxAvatarSize);
                final fallbackRadius = (avatarSize / 3).clamp(35.0, 100.0);
                final transcriptHeight = (flexibleHeight * 0.25).clamp(60.0, 180.0);

                return Column(
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Voice mode always uses static avatar;
                          // emotion images only in video mode
                          AvatarCircle(
                            characterId: widget.characterId,
                            radius: fallbackRadius,
                          ),
                          const SizedBox(height: 8),
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
                    if (chatState.transcript.isNotEmpty)
                      _buildTranscriptWithHeight(chatState, transcriptHeight),

                    // Controls
                    _buildControls(audioState),
                  ],
                );
              },
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

  Widget _buildTranscriptWithHeight(ChatState chatState, double height) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: ListView.builder(
        shrinkWrap: true,
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

  Widget _buildTranscript(ChatState chatState) {
    return SizedBox(
      height: Responsive.value<double>(context, phone: 120, tablet: 160, desktop: 180),
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
