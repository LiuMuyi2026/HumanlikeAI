import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../providers/character_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/avatar_circle.dart';
import '../../widgets/message_bubble.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String characterId;

  const ConversationScreen({super.key, required this.characterId});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final has = _textController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    // Load messages, then start polling for proactive AI messages
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(conversationProvider(widget.characterId).notifier);
      await notifier.loadMessages();
      _scrollToBottom();
      notifier.startPolling();
    });
    // Pagination on scroll up
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 100) {
      ref.read(conversationProvider(widget.characterId).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    ref.read(conversationProvider(widget.characterId).notifier).stopPolling();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await ref
        .read(conversationProvider(widget.characterId).notifier)
        .sendText(text);
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await ref
        .read(conversationProvider(widget.characterId).notifier)
        .sendImage(Uint8List.fromList(bytes), picked.name);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final convoState = ref.watch(conversationProvider(widget.characterId));
    final characterAsync =
        ref.watch(characterDetailProvider(widget.characterId));

    // Show errors + scroll on new messages from polling
    ref.listen(conversationProvider(widget.characterId), (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red.shade700,
          ),
        );
        ref
            .read(conversationProvider(widget.characterId).notifier)
            .clearError();
      }
      // Auto-scroll when new messages arrive (optimistic, AI response, or proactive)
      if (prev != null && next.messages.length > prev.messages.length) {
        _scrollToBottom();
      }
    });

    final character = characterAsync.valueOrNull;
    final characterName = character?.name ?? 'Chat';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarCircle(characterId: widget.characterId, radius: 18),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  characterName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (character?.relationshipType != null)
                  Text(
                    character!.relationshipType!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, size: 22),
            onPressed: () =>
                context.push('/call/${widget.characterId}?mode=voice'),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, size: 22),
            onPressed: () =>
                context.push('/call/${widget.characterId}?mode=video'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') {
                context.push('/character/${widget.characterId}');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('Profile'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: convoState.isLoading && convoState.messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : convoState.messages.isEmpty
                    ? _buildEmptyState(characterName)
                    : _buildMessageList(convoState),
          ),
          // Typing indicator
          if (convoState.isSending) _buildTypingIndicator(),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AvatarCircle(characterId: widget.characterId, radius: 48),
          const SizedBox(height: 16),
          Text(
            'Start chatting with $name',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to begin the conversation',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ConversationState state) {
    final api = ref.watch(apiClientProvider);
    final user = ref.watch(userProvider).valueOrNull;
    final userId = user?.id ?? '';
    final avatarUrl = api.avatarUrl(widget.characterId);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];

        // Build media URL for image/voice messages
        String? mediaUrl;
        if (message.mediaUrl != null) {
          mediaUrl = api.messageMediaUrl(
            widget.characterId,
            message.id,
            userId,
          );
        }

        return MessageBubble(
          message: message,
          avatarUrl: message.isAi ? avatarUrl : null,
          mediaUrl: mediaUrl,
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Typing...',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // Attachment button
          IconButton(
            icon: Icon(
              Icons.add_photo_alternate_outlined,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            onPressed: _pickAndSendImage,
          ),
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Send button
          IconButton(
            icon: Icon(
              _hasText ? Icons.send : Icons.mic,
              color: _hasText ? AppTheme.primary : Colors.white.withValues(alpha: 0.6),
            ),
            onPressed: _hasText ? _sendText : null,
          ),
        ],
      ),
    );
  }
}
