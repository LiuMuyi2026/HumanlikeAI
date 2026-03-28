import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../models/user.dart';
import 'user_provider.dart';

final charactersProvider =
    AsyncNotifierProvider<CharactersNotifier, List<Character>>(
  CharactersNotifier.new,
);

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  /// Gets the user, re-fetching if cached value is null.
  Future<User> _requireUser() async {
    var user = await ref.read(userProvider.future);
    if (user == null) {
      // Cached null from earlier failure — invalidate and retry
      ref.invalidate(userProvider);
      user = await ref.read(userProvider.future);
    }
    if (user == null) {
      throw Exception('Could not load user. Is the backend running?');
    }
    return user;
  }

  @override
  Future<List<Character>> build() async {
    try {
      final user = await ref.watch(userProvider.future);
      if (user == null) return [];
      final api = ref.read(apiClientProvider);
      return api.listCharacters(user.id);
    } catch (_) {
      return [];
    }
  }

  Future<Character> create(Map<String, dynamic> body) async {
    final user = await _requireUser();
    final api = ref.read(apiClientProvider);
    final character = await api.createCharacter(user.id, body);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, character]);
    return character;
  }

  Future<Character> updateCharacter(String id, Map<String, dynamic> body) async {
    final user = await _requireUser();
    final api = ref.read(apiClientProvider);
    final updated = await api.updateCharacter(id, user.id, body);
    final current = state.valueOrNull ?? [];
    state = AsyncData(
      current.map((c) => c.id == id ? updated : c).toList(),
    );
    return updated;
  }

  Future<void> delete(String id) async {
    final user = await _requireUser();
    final api = ref.read(apiClientProvider);
    await api.deleteCharacter(id, user.id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((c) => c.id != id).toList());
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final characterDetailProvider =
    FutureProvider.family<Character, String>((ref, id) async {
  final user = await ref.watch(userProvider.future);
  if (user == null) {
    ref.invalidate(userProvider);
    final retried = await ref.read(userProvider.future);
    if (retried == null) throw Exception('User not found');
    final api = ref.read(apiClientProvider);
    return api.getCharacter(id, retried.id);
  }
  final api = ref.read(apiClientProvider);
  return api.getCharacter(id, user.id);
});

final emotionPackStatusProvider =
    FutureProvider.family<EmotionPackStatus, String>((ref, charId) async {
  final user = await ref.watch(userProvider.future);
  if (user == null) {
    throw Exception('User not found');
  }
  final api = ref.read(apiClientProvider);
  return api.getEmotionPackStatus(charId, user.id);
});
