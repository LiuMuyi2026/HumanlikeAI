import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/device_id_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final deviceIdProvider = FutureProvider<String>((ref) async {
  return DeviceIdService.getOrCreate();
});

final userProvider =
    AsyncNotifierProvider<UserNotifier, User?>(UserNotifier.new);

class UserNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final deviceId = await ref.watch(deviceIdProvider.future);
    final api = ref.read(apiClientProvider);
    try {
      return await api.getUser(deviceId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> updateUser({
    String? displayName,
    String? relationshipStatus,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final api = ref.read(apiClientProvider);
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (relationshipStatus != null) {
      body['relationship_status'] = relationshipStatus;
    }

    final updated = await api.updateUser(current.id, body);
    state = AsyncData(updated);
  }
}
