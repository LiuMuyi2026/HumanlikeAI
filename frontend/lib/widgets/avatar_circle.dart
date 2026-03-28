import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/user_provider.dart';

class AvatarCircle extends ConsumerWidget {
  final String characterId;
  final double radius;

  const AvatarCircle({
    super.key,
    required this.characterId,
    this.radius = 32,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final url = api.avatarUrl(characterId);

    final fallback = Icon(
      Icons.person,
      size: radius,
      color: AppTheme.primary.withValues(alpha: 0.5),
    );

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.surfaceLight,
      child: ClipOval(
        child: kIsWeb
            ? Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : CachedNetworkImage(
                imageUrl: url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
