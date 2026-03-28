import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import 'user_provider.dart';

class ConversationState {
  final List<Message> messages;
  final bool isLoading;
  final bool isSending;
  final bool hasMore;
  final String? error;

  const ConversationState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.hasMore = false,
    this.error,
  });

  ConversationState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    bool? hasMore,
    String? error,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class ConversationNotifier extends StateNotifier<ConversationState> {
  final Ref _ref;
  final String characterId;
  String? _userId;
  Timer? _pollTimer;

  ConversationNotifier(this._ref, this.characterId)
      : super(const ConversationState());

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _ref.read(userProvider.future);
      if (user == null) throw Exception('User not found');
      _userId = user.id;

      final api = _ref.read(apiClientProvider);
      final result = await api.listMessages(characterId, user.id);
      state = state.copyWith(
        messages: result.messages,
        hasMore: result.hasMore,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoading: true);
    try {
      final api = _ref.read(apiClientProvider);
      final before = state.messages.first.createdAt;
      final result = await api.listMessages(
        characterId,
        _userId!,
        before: before,
      );
      state = state.copyWith(
        messages: [...result.messages, ...state.messages],
        hasMore: result.hasMore,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendText(String text) async {
    if (_userId == null) return;

    // Optimistic: show user message immediately
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = Message(
      id: tempId,
      characterId: characterId,
      userId: _userId!,
      role: 'user',
      contentType: 'text',
      content: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
      error: null,
    );

    try {
      final api = _ref.read(apiClientProvider);
      final newMessages = await api.sendTextMessage(
        characterId,
        _userId!,
        text,
      );
      // Replace temp message with real messages (user + AI response)
      final updated = state.messages.where((m) => m.id != tempId).toList();
      state = state.copyWith(
        messages: [...updated, ...newMessages],
        isSending: false,
      );
    } catch (e) {
      // Keep the optimistic message visible on error
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendImage(Uint8List imageBytes, String filename) async {
    if (_userId == null) return;

    // Optimistic: show placeholder user message immediately
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = Message(
      id: tempId,
      characterId: characterId,
      userId: _userId!,
      role: 'user',
      contentType: 'image',
      content: '[Image]',
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
      error: null,
    );

    try {
      final api = _ref.read(apiClientProvider);
      final newMessages = await api.sendImageMessage(
        characterId,
        _userId!,
        imageBytes,
        filename,
      );
      final updated = state.messages.where((m) => m.id != tempId).toList();
      state = state.copyWith(
        messages: [...updated, ...newMessages],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendVoice(Uint8List audioBytes, String filename) async {
    if (_userId == null) return;
    state = state.copyWith(isSending: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      final newMessages = await api.sendVoiceMessage(
        characterId,
        _userId!,
        audioBytes,
        filename,
      );
      state = state.copyWith(
        messages: [...state.messages, ...newMessages],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  void startPolling() {
    stopPolling();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollNewMessages(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollNewMessages() async {
    if (_userId == null || state.messages.isEmpty) return;
    try {
      final api = _ref.read(apiClientProvider);
      final lastTime = state.messages.last.createdAt;
      final newMessages = await api.listNewMessages(
        characterId,
        _userId!,
        lastTime,
      );
      if (newMessages.isNotEmpty && mounted) {
        state = state.copyWith(
          messages: [...state.messages, ...newMessages],
        );
      }
    } catch (_) {
      // Silently ignore polling errors
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

final conversationProvider = StateNotifierProvider.autoDispose
    .family<ConversationNotifier, ConversationState, String>(
  (ref, characterId) => ConversationNotifier(ref, characterId),
);
