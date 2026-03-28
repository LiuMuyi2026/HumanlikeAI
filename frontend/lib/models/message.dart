class Message {
  final String id;
  final String characterId;
  final String userId;
  final String role; // 'user' or 'ai'
  final String contentType; // 'text', 'image', 'voice'
  final String? content;
  final String? mediaUrl;
  final String? emotion;
  final double? valence;
  final double? arousal;
  final String? intensity;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.role,
    required this.contentType,
    this.content,
    this.mediaUrl,
    this.emotion,
    this.valence,
    this.arousal,
    this.intensity,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isAi => role == 'ai';
  bool get isText => contentType == 'text';
  bool get isImage => contentType == 'image';
  bool get isVoice => contentType == 'voice';

  String get emotionKey {
    final e = emotion ?? 'neutral';
    final i = intensity ?? 'low';
    return '${e}_$i';
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      contentType: json['content_type'] as String,
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      emotion: json['emotion'] as String?,
      valence: (json['valence'] as num?)?.toDouble(),
      arousal: (json['arousal'] as num?)?.toDouble(),
      intensity: json['intensity'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
