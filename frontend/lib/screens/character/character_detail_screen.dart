import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/responsive.dart';
import '../../config/theme.dart';
import '../../models/character.dart';
import '../../providers/character_provider.dart';
import '../../providers/user_provider.dart';

class CharacterDetailScreen extends ConsumerStatefulWidget {
  final String characterId;

  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  String? _prevRelationshipType;
  int? _prevFamiliarityLevel;

  @override
  Widget build(BuildContext context) {
    final characterAsync = ref.watch(characterDetailProvider(widget.characterId));

    // Feature 4: Detect relationship changes and show SnackBar
    ref.listen<AsyncValue<Character>>(
      characterDetailProvider(widget.characterId),
      (prev, next) {
        final prevChar = prev?.valueOrNull;
        final nextChar = next.valueOrNull;
        if (prevChar == null || nextChar == null) return;

        final oldType = _prevRelationshipType ?? prevChar.relationshipType;
        final oldFam = _prevFamiliarityLevel ?? prevChar.familiarityLevel;
        final typeChanged = nextChar.relationshipType != oldType;
        final famChanged = nextChar.familiarityLevel != oldFam;

        if (typeChanged || famChanged) {
          _prevRelationshipType = nextChar.relationshipType;
          _prevFamiliarityLevel = nextChar.familiarityLevel;

          final parts = <String>[];
          if (typeChanged) {
            parts.add('${oldType ?? "None"} → ${nextChar.relationshipType ?? "None"}');
          }
          if (famChanged) {
            parts.add('Familiarity $oldFam → ${nextChar.familiarityLevel}');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Relationship updated: ${parts.join(", ")}'),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );

    return Scaffold(
      body: characterAsync.when(
        data: (character) {
          final api = ref.watch(apiClientProvider);
          final avatarUrl = api.avatarUrl(widget.characterId);
          final hasAvatar = character.hasAvatar;

          return Responsive.constrain(
            context,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: Responsive.value<double>(context, phone: 320, tablet: 400, desktop: 450),
                pinned: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () =>
                        context.push('/character/${widget.characterId}/edit'),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Character'),
                            content: Text(
                              'Are you sure you want to delete ${character.name}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await ref
                              .read(charactersProvider.notifier)
                              .delete(widget.characterId);
                          if (context.mounted) context.go('/contacts');
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background: avatar image or gradient
                      if (hasAvatar)
                        kIsWeb
                            ? Image.network(
                                avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: AppTheme.backgroundGradient,
                                  ),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: AppTheme.backgroundGradient,
                                  ),
                                ),
                              )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: AppTheme.backgroundGradient,
                          ),
                        ),
                      // Gradient overlay for text readability
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                            stops: const [0.4, 1.0],
                          ),
                        ),
                      ),
                      // Name and relationship at bottom
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              character.name,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (character.relationshipType != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  character.relationshipType!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                SliverPadding(
                  padding: Responsive.contentPadding(context).copyWith(top: 20, bottom: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Action buttons — Voice Call, Video Call, Gallery
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context
                                .push('/call/${widget.characterId}?mode=voice'),
                            icon: const Icon(Icons.call, size: 20),
                            label: const Text('Voice Call'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context
                                .push('/call/${widget.characterId}?mode=video'),
                            icon: const Icon(Icons.videocam, size: 20),
                            label: const Text('Video Call'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: AppTheme.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 56,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => context
                                .push('/character/${widget.characterId}/gallery'),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: const BorderSide(color: AppTheme.primary),
                            ),
                            child: const Icon(Icons.photo_library, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Emotion pack status
                    _buildEmotionPackRow(ref),
                    const SizedBox(height: 24),

                    // Info section
                    _buildInfoSection('Details', [
                      if (character.gender != null)
                        _infoRow('Gender', character.gender!),
                      if (character.region != null)
                        _infoRow('Region', character.region!),
                      if (character.occupation != null)
                        _infoRow('Occupation', character.occupation!),
                      if (character.mbti != null)
                        _infoRow('MBTI', character.mbti!),
                      if (character.politicalLeaning != null)
                        _infoRow('Political Leaning',
                            character.politicalLeaning!),
                      _infoRow('Familiarity',
                          '${character.familiarityLevel} / 10'),
                    ]),

                    if (character.personalityTraits != null &&
                        character.personalityTraits!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Personality',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: character.personalityTraits!
                            .map(
                              (trait) => Chip(
                                label: Text(
                                  trait,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.2),
                                side: BorderSide.none,
                              ),
                            )
                            .toList(),
                      ),
                    ],

                    if (character.skills != null &&
                        character.skills!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Skills',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: character.skills!
                            .map(
                              (skill) => Chip(
                                label: Text(
                                  skill,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                backgroundColor:
                                    AppTheme.accent.withValues(alpha: 0.2),
                                side: BorderSide.none,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ]),
                ),
              ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.accent),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(
                  characterDetailProvider(widget.characterId),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmotionPackRow(WidgetRef ref) {
    final packAsync = ref.watch(emotionPackStatusProvider(widget.characterId));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_emotions, size: 20, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Text(
            'Emotion Pack',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          packAsync.when(
            data: (status) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: status.isComplete
                    ? Colors.green.withValues(alpha: 0.2)
                    : status.hasAny
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status.isComplete
                    ? '${status.generated}/${status.totalExpected}'
                    : status.hasAny
                        ? '${status.generated}/${status.totalExpected}'
                        : 'Not generated',
                style: TextStyle(
                  fontSize: 12,
                  color: status.isComplete
                      ? Colors.green
                      : status.hasAny
                          ? Colors.orange
                          : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            loading: () => const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, _) => Text(
              'Not generated',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: Responsive.value<double>(context, phone: 120, tablet: 140, desktop: 160),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
