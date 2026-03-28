class Character {
  final String id;
  final String userId;
  final String name;
  final String? gender;
  final String? region;
  final String? occupation;
  final List<String>? personalityTraits;
  final String? mbti;
  final String? politicalLeaning;
  final String? relationshipType;
  final int familiarityLevel;
  final List<String>? skills;
  final String? avatarPrompt;
  final String? avatarPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Character({
    required this.id,
    required this.userId,
    required this.name,
    this.gender,
    this.region,
    this.occupation,
    this.personalityTraits,
    this.mbti,
    this.politicalLeaning,
    this.relationshipType,
    this.familiarityLevel = 5,
    this.skills,
    this.avatarPrompt,
    this.avatarPath,
    this.createdAt,
    this.updatedAt,
  });

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      gender: json['gender'] as String?,
      region: json['region'] as String?,
      occupation: json['occupation'] as String?,
      personalityTraits: (json['personality_traits'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      mbti: json['mbti'] as String?,
      politicalLeaning: json['political_leaning'] as String?,
      relationshipType: json['relationship_type'] as String?,
      familiarityLevel: json['familiarity_level'] as int? ?? 5,
      skills: (json['skills'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      avatarPrompt: json['avatar_prompt'] as String?,
      avatarPath: json['avatar_path'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (gender != null) 'gender': gender,
    if (region != null) 'region': region,
    if (occupation != null) 'occupation': occupation,
    if (personalityTraits != null) 'personality_traits': personalityTraits,
    if (mbti != null) 'mbti': mbti,
    if (politicalLeaning != null) 'political_leaning': politicalLeaning,
    if (relationshipType != null) 'relationship_type': relationshipType,
    'familiarity_level': familiarityLevel,
    if (skills != null) 'skills': skills,
  };

  bool get hasAvatar => avatarPath != null && avatarPath!.isNotEmpty;

  Character copyWith({
    String? name,
    String? gender,
    String? region,
    String? occupation,
    List<String>? personalityTraits,
    String? mbti,
    String? politicalLeaning,
    String? relationshipType,
    int? familiarityLevel,
    List<String>? skills,
    String? avatarPrompt,
    String? avatarPath,
  }) {
    return Character(
      id: id,
      userId: userId,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      region: region ?? this.region,
      occupation: occupation ?? this.occupation,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      mbti: mbti ?? this.mbti,
      politicalLeaning: politicalLeaning ?? this.politicalLeaning,
      relationshipType: relationshipType ?? this.relationshipType,
      familiarityLevel: familiarityLevel ?? this.familiarityLevel,
      skills: skills ?? this.skills,
      avatarPrompt: avatarPrompt ?? this.avatarPrompt,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class CharacterImage {
  final String id;
  final String characterId;
  final String imagePath;
  final String? promptUsed;
  final bool isAvatar;
  final DateTime? createdAt;

  const CharacterImage({
    required this.id,
    required this.characterId,
    required this.imagePath,
    this.promptUsed,
    this.isAvatar = false,
    this.createdAt,
  });

  factory CharacterImage.fromJson(Map<String, dynamic> json) {
    return CharacterImage(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      imagePath: json['image_path'] as String,
      promptUsed: json['prompt_used'] as String?,
      isAvatar: json['is_avatar'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class CharacterEmotionImage {
  final String id;
  final String characterId;
  final String emotionKey;
  final String imagePath;
  final String? promptUsed;
  final DateTime? createdAt;

  const CharacterEmotionImage({
    required this.id,
    required this.characterId,
    required this.emotionKey,
    required this.imagePath,
    this.promptUsed,
    this.createdAt,
  });

  factory CharacterEmotionImage.fromJson(Map<String, dynamic> json) {
    return CharacterEmotionImage(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      emotionKey: json['emotion_key'] as String,
      imagePath: json['image_path'] as String,
      promptUsed: json['prompt_used'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class EmotionPackStatus {
  final String characterId;
  final int totalExpected;
  final int generated;
  final List<String> emotionKeys;
  final List<CharacterEmotionImage> images;

  const EmotionPackStatus({
    required this.characterId,
    required this.totalExpected,
    required this.generated,
    required this.emotionKeys,
    required this.images,
  });

  bool get isComplete => generated >= totalExpected;
  bool get hasAny => generated > 0;

  factory EmotionPackStatus.fromJson(Map<String, dynamic> json) {
    return EmotionPackStatus(
      characterId: json['character_id'] as String,
      totalExpected: json['total_expected'] as int,
      generated: json['generated'] as int,
      emotionKeys: (json['emotion_keys'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      images: (json['images'] as List<dynamic>)
          .map((e) => CharacterEmotionImage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
