class AppConstants {
  AppConstants._();

  static const String appName = 'HLAI';

  // API URLs - change these for production
  static const String apiBaseUrl = 'http://localhost:8000';
  static const String apiPath = '/api';
  static const String wsUrl = 'ws://localhost:8000/ws';

  // REST endpoints
  static String usersPath(String deviceId) => '$apiPath/users/$deviceId';
  static String userUpdatePath(String userId) => '$apiPath/users/$userId';
  static String charactersPath() => '$apiPath/characters';
  static String characterPath(String id) => '$apiPath/characters/$id';
  static String characterAvatarPath(String id) => '$apiPath/characters/$id/avatar';
  static String characterImagesPath(String id) => '$apiPath/characters/$id/images';
  static String characterImagePath(String charId, String imgId) =>
      '$apiPath/characters/$charId/images/$imgId';
  static String setAvatarPath(String charId, String imgId) =>
      '$apiPath/characters/$charId/images/$imgId/set-avatar';
  static String generateAvatarPath(String id) => '$apiPath/characters/$id/generate-avatar';
  static String generateImagePath(String id) => '$apiPath/characters/$id/generate-image';
  static String emotionPackPath(String id) => '$apiPath/characters/$id/emotion-pack';
  static String emotionImagePath(String charId, String emotionKey) =>
      '$apiPath/characters/$charId/emotion-pack/$emotionKey/file';

  // Messages
  static String messagesPath(String charId) => '$apiPath/characters/$charId/messages';
  static String messageImagePath(String charId) =>
      '$apiPath/characters/$charId/messages/image';
  static String messageVoicePath(String charId) =>
      '$apiPath/characters/$charId/messages/voice';
  static String messagesNewPath(String charId) =>
      '$apiPath/characters/$charId/messages/new';
  static String messageMediaPath(String charId, String msgId) =>
      '$apiPath/characters/$charId/messages/$msgId/media';

  // Audio
  static const int inputSampleRate = 16000;
  static const int outputSampleRate = 24000;
  static const String inputMimeType = 'audio/pcm;rate=16000';

  // SharedPreferences keys
  // Keep legacy key so existing users don't lose their data
  static const String deviceIdKey = 'soulmate_device_id';

  // MBTI types
  static const List<String> mbtiTypes = [
    'INTJ', 'INTP', 'ENTJ', 'ENTP',
    'INFJ', 'INFP', 'ENFJ', 'ENFP',
    'ISTJ', 'ISFJ', 'ESTJ', 'ESFJ',
    'ISTP', 'ISFP', 'ESTP', 'ESFP',
  ];

  // Personality trait suggestions
  static const List<String> personalityTraits = [
    'Humorous', 'Empathetic', 'Intellectual', 'Adventurous',
    'Creative', 'Calm', 'Energetic', 'Witty',
    'Caring', 'Ambitious', 'Romantic', 'Playful',
    'Philosophical', 'Sarcastic', 'Optimistic', 'Mysterious',
  ];

  // Gender options
  static const List<String> genderOptions = [
    'Male', 'Female', 'Custom',
  ];

  // Relationship types
  static const List<String> relationshipTypes = [
    'Friend', 'Best Friend', 'Romantic Partner', 'Ex-Partner',
    'Mentor', 'Companion', 'Confidant', 'Study Buddy', 'Advisor',
    'Acquaintance', 'Rival', 'Frenemy', 'Critic',
    'Nemesis', 'Stranger', 'Colleague',
  ];

  // Skills
  static const List<String> skills = [
    'Cooking', 'Music', 'Therapy', 'Counseling', 'Storytelling',
    'Language Tutoring', 'Fitness Coaching', 'Art & Drawing',
    'Programming', 'Philosophy', 'History', 'Science',
    'Travel Guide', 'Fashion Advice', 'Financial Planning',
    'Meditation', 'Gaming', 'Writing', 'Photography', 'Singing',
  ];

  // Political leaning labels
  static const List<String> politicalLabels = [
    'Very Liberal', 'Liberal', 'Moderate', 'Conservative', 'Very Conservative',
  ];
}
