import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';

/// Displays the character's emotion image with crossfade transitions.
///
/// If an emotion pack exists for the character, shows the matching emotion
/// image (e.g. "happy_mid"). Falls back to the default avatar + emoji
/// indicator if no emotion pack is available.
class EmotionAvatar extends ConsumerWidget {
  final String characterId;
  final double size;
  final bool hasEmotionPack;

  const EmotionAvatar({
    super.key,
    required this.characterId,
    this.size = 200,
    this.hasEmotionPack = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final api = ref.watch(apiClientProvider);

    if (!hasEmotionPack) {
      // Fallback: avatar + emoji indicator
      return _buildFallback(context, ref, chatState);
    }

    final emotionKey = chatState.emotionKey;
    final imageUrl = api.emotionImageUrl(characterId, emotionKey);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: ClipRRect(
        key: ValueKey(emotionKey),
        borderRadius: BorderRadius.circular(size * 0.1),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildImage(imageUrl),
        ),
      ),
    );
  }

  Widget _buildFallback(
    BuildContext context,
    WidgetRef ref,
    ChatState chatState,
  ) {
    final api = ref.watch(apiClientProvider);
    final avatarUrl = api.avatarUrl(characterId);

    return ClipOval(
      child: SizedBox(
        width: size * 0.7,
        height: size * 0.7,
        child: _buildImage(avatarUrl),
      ),
    );
  }

  Widget _buildImage(String url) {
    final fallback = Container(
      color: AppTheme.surfaceLight,
      child: Icon(
        Icons.person,
        size: size * 0.4,
        color: AppTheme.primary.withValues(alpha: 0.5),
      ),
    );

    if (kIsWeb) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        color: AppTheme.surfaceLight,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, _, _) => fallback,
    );
  }
}
