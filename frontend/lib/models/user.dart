class User {
  final String id;
  final String deviceId;
  final String? displayName;
  final Map<String, dynamic>? preferences;
  final String? relationshipStatus;
  final Map<String, dynamic>? extractedFacts;

  const User({
    required this.id,
    required this.deviceId,
    this.displayName,
    this.preferences,
    this.relationshipStatus,
    this.extractedFacts,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      displayName: json['display_name'] as String?,
      preferences: json['preferences'] as Map<String, dynamic>?,
      relationshipStatus: json['relationship_status'] as String?,
      extractedFacts: json['extracted_facts'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    if (displayName != null) 'display_name': displayName,
    if (preferences != null) 'preferences': preferences,
    if (relationshipStatus != null) 'relationship_status': relationshipStatus,
    if (extractedFacts != null) 'extracted_facts': extractedFacts,
  };

  User copyWith({
    String? displayName,
    Map<String, dynamic>? preferences,
    String? relationshipStatus,
  }) {
    return User(
      id: id,
      deviceId: deviceId,
      displayName: displayName ?? this.displayName,
      preferences: preferences ?? this.preferences,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      extractedFacts: extractedFacts,
    );
  }
}
