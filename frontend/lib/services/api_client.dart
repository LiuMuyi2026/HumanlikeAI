import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/constants.dart';
import '../models/character.dart';
import '../models/message.dart';
import '../models/user.dart';

class ApiClient {
  final Dio _dio;

  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

  // -- Users --

  Future<User> getUser(String deviceId) async {
    final response = await _dio.get(AppConstants.usersPath(deviceId));
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  Future<User> updateUser(String userId, Map<String, dynamic> body) async {
    final response = await _dio.put(
      AppConstants.userUpdatePath(userId),
      data: body,
    );
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  // -- Characters --

  Future<Character> createCharacter(String userId, Map<String, dynamic> body) async {
    final response = await _dio.post(
      AppConstants.charactersPath(),
      data: body,
      queryParameters: {'user_id': userId},
    );
    return Character.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Character>> listCharacters(String userId) async {
    final response = await _dio.get(
      AppConstants.charactersPath(),
      queryParameters: {'user_id': userId},
    );
    final data = response.data as Map<String, dynamic>;
    final list = data['characters'] as List<dynamic>;
    return list
        .map((e) => Character.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Character> getCharacter(String id, String userId) async {
    final response = await _dio.get(
      AppConstants.characterPath(id),
      queryParameters: {'user_id': userId},
    );
    return Character.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Character> updateCharacter(
    String id,
    String userId,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.put(
      AppConstants.characterPath(id),
      data: body,
      queryParameters: {'user_id': userId},
    );
    return Character.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCharacter(String id, String userId) async {
    await _dio.delete(
      AppConstants.characterPath(id),
      queryParameters: {'user_id': userId},
    );
  }

  // -- Character Images --

  Future<CharacterImage> generateAvatar(
    String characterId,
    String userId, {
    String? prompt,
  }) async {
    final response = await _dio.post(
      AppConstants.generateAvatarPath(characterId),
      data: prompt != null ? {'prompt': prompt} : null,
      queryParameters: {'user_id': userId},
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    return CharacterImage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CharacterImage> generateImage(
    String characterId,
    String userId, {
    String? prompt,
    bool useAvatar = false,
  }) async {
    final response = await _dio.post(
      AppConstants.generateImagePath(characterId),
      data: prompt != null ? {'prompt': prompt} : null,
      queryParameters: {'user_id': userId, 'use_avatar': useAvatar},
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    return CharacterImage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CharacterImage>> listImages(
    String characterId,
    String userId,
  ) async {
    final response = await _dio.get(
      AppConstants.characterImagesPath(characterId),
      queryParameters: {'user_id': userId},
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => CharacterImage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setAvatar(
    String characterId,
    String imageId,
    String userId,
  ) async {
    await _dio.put(
      AppConstants.setAvatarPath(characterId, imageId),
      queryParameters: {'user_id': userId},
    );
  }

  Future<void> deleteImage(
    String characterId,
    String imageId,
    String userId,
  ) async {
    await _dio.delete(
      AppConstants.characterImagePath(characterId, imageId),
      queryParameters: {'user_id': userId},
    );
  }

  // -- Emotion Pack --

  Future<EmotionPackStatus> generateEmotionPack(
    String characterId,
    String userId,
  ) async {
    final response = await _dio.post(
      AppConstants.emotionPackPath(characterId),
      queryParameters: {'user_id': userId},
    );
    return EmotionPackStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<EmotionPackStatus> getEmotionPackStatus(
    String characterId,
    String userId,
  ) async {
    final response = await _dio.get(
      AppConstants.emotionPackPath(characterId),
      queryParameters: {'user_id': userId},
    );
    return EmotionPackStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteEmotionPack(
    String characterId,
    String userId,
  ) async {
    await _dio.delete(
      AppConstants.emotionPackPath(characterId),
      queryParameters: {'user_id': userId},
    );
  }

  /// Returns the full URL for a character's emotion image.
  String emotionImageUrl(String characterId, String emotionKey) {
    return '${AppConstants.apiBaseUrl}${AppConstants.emotionImagePath(characterId, emotionKey)}';
  }

  /// Returns the full URL for a character's avatar image.
  String avatarUrl(String characterId) {
    return '${AppConstants.apiBaseUrl}${AppConstants.characterAvatarPath(characterId)}';
  }

  // -- Chat Messages --

  Future<({List<Message> messages, bool hasMore})> listMessages(
    String characterId,
    String userId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final response = await _dio.get(
      AppConstants.messagesPath(characterId),
      queryParameters: {
        'user_id': userId,
        'limit': limit,
        if (before != null) 'before': before.toIso8601String(),
      },
    );
    final data = response.data as Map<String, dynamic>;
    final list = data['messages'] as List<dynamic>;
    final messages = list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
    return (messages: messages, hasMore: data['has_more'] as bool);
  }

  Future<List<Message>> listNewMessages(
    String characterId,
    String userId,
    DateTime after,
  ) async {
    final response = await _dio.get(
      AppConstants.messagesNewPath(characterId),
      queryParameters: {
        'user_id': userId,
        'after': after.toUtc().toIso8601String(),
      },
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> sendTextMessage(
    String characterId,
    String userId,
    String text,
  ) async {
    final response = await _dio.post(
      AppConstants.messagesPath(characterId),
      data: {'content': text},
      queryParameters: {'user_id': userId},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> sendImageMessage(
    String characterId,
    String userId,
    Uint8List imageBytes,
    String filename,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(imageBytes, filename: filename),
    });
    final response = await _dio.post(
      AppConstants.messageImagePath(characterId),
      data: formData,
      queryParameters: {'user_id': userId},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> sendVoiceMessage(
    String characterId,
    String userId,
    Uint8List audioBytes,
    String filename,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        audioBytes,
        filename: filename,
        contentType: DioMediaType('audio', 'webm'),
      ),
    });
    final response = await _dio.post(
      AppConstants.messageVoicePath(characterId),
      data: formData,
      queryParameters: {'user_id': userId},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String messageMediaUrl(String characterId, String messageId, String userId) {
    return '${AppConstants.apiBaseUrl}${AppConstants.messageMediaPath(characterId, messageId)}?user_id=$userId';
  }
}
