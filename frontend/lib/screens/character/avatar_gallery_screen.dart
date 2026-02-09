import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/constants.dart';
import '../../config/responsive.dart';
import '../../config/theme.dart';
import '../../models/character.dart';
import '../../providers/character_provider.dart';
import '../../providers/user_provider.dart';

final _imagesProvider =
    FutureProvider.family<List<CharacterImage>, String>((ref, charId) async {
  final user = await ref.watch(userProvider.future);
  if (user == null) return [];
  final api = ref.read(apiClientProvider);
  return api.listImages(charId, user.id);
});

class AvatarGalleryScreen extends ConsumerStatefulWidget {
  final String characterId;

  const AvatarGalleryScreen({super.key, required this.characterId});

  @override
  ConsumerState<AvatarGalleryScreen> createState() =>
      _AvatarGalleryScreenState();
}

class _AvatarGalleryScreenState extends ConsumerState<AvatarGalleryScreen> {
  bool _generating = false;
  bool _generatingEmotionPack = false;
  final _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generateAvatar() async {
    setState(() => _generating = true);
    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);
      final prompt = _promptController.text.trim();
      await api.generateAvatar(
        widget.characterId,
        user!.id,
        prompt: prompt.isNotEmpty ? prompt : null,
      );
      _promptController.clear();
      ref.invalidate(_imagesProvider(widget.characterId));
      ref.invalidate(characterDetailProvider(widget.characterId));
      ref.invalidate(charactersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateImage({bool useAvatar = false}) async {
    setState(() => _generating = true);
    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);
      final prompt = _promptController.text.trim();
      await api.generateImage(
        widget.characterId,
        user!.id,
        prompt: prompt.isNotEmpty ? prompt : null,
        useAvatar: useAvatar,
      );
      _promptController.clear();
      ref.invalidate(_imagesProvider(widget.characterId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateEmotionPack() async {
    setState(() => _generatingEmotionPack = true);
    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);

      // Kick off generation (returns immediately, runs in background)
      await api.generateEmotionPack(widget.characterId, user!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generating emotion pack...')),
        );
      }

      // Poll for progress every 5 seconds until complete
      _pollEmotionPackProgress();
    } catch (e) {
      if (mounted) {
        setState(() => _generatingEmotionPack = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start emotion pack: $e')),
        );
      }
    }
  }

  Future<void> _pollEmotionPackProgress() async {
    final user = await ref.read(userProvider.future);
    if (user == null) return;
    final api = ref.read(apiClientProvider);

    while (mounted && _generatingEmotionPack) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;

      try {
        final status = await api.getEmotionPackStatus(
          widget.characterId,
          user.id,
        );
        ref.invalidate(emotionPackStatusProvider(widget.characterId));

        if (status.isComplete) {
          if (mounted) {
            setState(() => _generatingEmotionPack = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Emotion pack complete: ${status.generated}/${status.totalExpected}',
                ),
              ),
            );
          }
          return;
        }
      } catch (_) {
        // Polling error — just retry next cycle
      }
    }
  }

  Future<void> _deleteEmotionPack() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Emotion Pack'),
        content: const Text(
          'Delete all emotion images? You can regenerate them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);
      await api.deleteEmotionPack(widget.characterId, user!.id);
      ref.invalidate(emotionPackStatusProvider(widget.characterId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emotion pack deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _setAsAvatar(CharacterImage image) async {
    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);
      await api.setAvatar(widget.characterId, image.id, user!.id);
      ref.invalidate(_imagesProvider(widget.characterId));
      ref.invalidate(characterDetailProvider(widget.characterId));
      ref.invalidate(charactersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(CharacterImage image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final user = await ref.read(userProvider.future);
      final api = ref.read(apiClientProvider);
      await api.deleteImage(widget.characterId, image.id, user!.id);
      ref.invalidate(_imagesProvider(widget.characterId));
      if (image.isAvatar) {
        ref.invalidate(characterDetailProvider(widget.characterId));
        ref.invalidate(charactersProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagesAsync = ref.watch(_imagesProvider(widget.characterId));

    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: Responsive.constrain(
        context,
        child: Column(
          children: [
            // Prompt input + generate buttons
            Padding(
              padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    hintText: 'Optional prompt for image generation...',
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _generating ? null : _generateAvatar,
                        icon: _generating
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.face, size: 18),
                        label: const Text('Avatar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generating ? null : _generateImage,
                        icon: const Icon(Icons.image, size: 18),
                        label: const Text('Image'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generating
                            ? null
                            : () => _generateImage(useAvatar: true),
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: const Text('From Avatar'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.accent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Emotion pack section
          _buildEmotionPackSection(),

          // Image grid
          Expanded(
            child: imagesAsync.when(
              data: (images) {
                if (images.isEmpty) {
                  return Center(
                    child: Text(
                      'No images yet.\nGenerate an avatar or image above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final image = images[index];
                    final imageUrl =
                        '${AppConstants.apiBaseUrl}${AppConstants.characterImagePath(widget.characterId, image.id)}/file';

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: AppTheme.surfaceLight,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: AppTheme.surfaceLight,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                          // Avatar badge
                          if (image.isAvatar)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Avatar',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          // Action buttons overlay at bottom
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!image.isAvatar)
                                  _actionIcon(
                                    icon: Icons.face,
                                    tooltip: 'Set as Avatar',
                                    onTap: () => _setAsAvatar(image),
                                  ),
                                const SizedBox(width: 4),
                                _actionIcon(
                                  icon: Icons.delete,
                                  tooltip: 'Delete',
                                  color: Colors.red,
                                  onTap: () => _deleteImage(image),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
              error: (error, stack) => Center(
                child: Text('Error: $error'),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionPackSection() {
    final packAsync =
        ref.watch(emotionPackStatusProvider(widget.characterId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Row(
            children: [
              const Icon(Icons.emoji_emotions, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Emotion Pack',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              packAsync.when(
                data: (status) => Text(
                  '${status.generated}/${status.totalExpected}',
                  style: TextStyle(
                    fontSize: 13,
                    color: status.isComplete
                        ? Colors.green
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                loading: () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => Text(
                  '0/?',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_generatingEmotionPack || _generating) ? null : _generateEmotionPack,
                  icon: _generatingEmotionPack
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _generatingEmotionPack ? 'Generating...' : 'Generate Emotion Pack',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              packAsync.when(
                data: (status) => status.hasAny
                    ? IconButton(
                        onPressed: _deleteEmotionPack,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Delete emotion pack',
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
          // Show emotion image grid preview if pack exists
          packAsync.when(
            data: (status) {
              if (!status.hasAny) return const SizedBox(height: 8);
              final api = ref.watch(apiClientProvider);
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: status.images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final img = status.images[index];
                      final url = api.emotionImageUrl(
                        widget.characterId,
                        img.emotionKey,
                      );
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 60,
                            height: 60,
                            color: AppTheme.surfaceLight,
                            child: Center(
                              child: Text(
                                img.emotionKey.split('_').first,
                                style: const TextStyle(fontSize: 8),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox(height: 8),
            error: (_, _) => const SizedBox(height: 8),
          ),
        ],
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: color ?? Colors.white,
        ),
      ),
    );
  }
}
