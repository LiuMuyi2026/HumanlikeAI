import 'package:flutter/material.dart';

import '../config/responsive.dart';
import '../config/theme.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final String? avatarUrl;
  final String? mediaUrl;

  const MessageBubble({
    super.key,
    required this.message,
    this.avatarUrl,
    this.mediaUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // AI avatar
          if (!isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.value(
                      context,
                      phone: MediaQuery.of(context).size.width * 0.7,
                      tablet: 400,
                      desktop: 480,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppTheme.primary
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: _buildContent(context),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (avatarUrl != null) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: Colors.grey.shade800,
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
      child: const Icon(Icons.smart_toy, size: 18, color: Colors.white70),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isImage) {
      final imgSize = Responsive.value<double>(
        context,
        phone: 200,
        tablet: 260,
        desktop: 300,
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: mediaUrl != null
            ? Image.network(
                mediaUrl!,
                width: imgSize,
                height: imgSize,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildImagePlaceholder(context),
              )
            : _buildImagePlaceholder(context),
      );
    }

    if (message.isVoice) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic,
              size: 18,
              color: message.isUser ? Colors.white : AppTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Voice message',
              style: TextStyle(
                fontSize: 14,
                color: message.isUser
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    // Text message
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        message.content ?? '',
        style: TextStyle(
          fontSize: 15,
          color: message.isUser
              ? Colors.white
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    final imgSize = Responsive.value<double>(
      context,
      phone: 200,
      tablet: 260,
      desktop: 300,
    );
    return Container(
      width: imgSize,
      height: imgSize,
      color: Colors.grey.shade800,
      child: const Icon(Icons.image, size: 48, color: Colors.white30),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
