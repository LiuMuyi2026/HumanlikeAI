import 'dart:convert';

class WsMessage {
  final String type;
  final Map<String, dynamic> payload;

  WsMessage({required this.type, required this.payload});

  factory WsMessage.fromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return WsMessage(
      type: map['type'] as String,
      payload: map['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  String toJson() {
    return jsonEncode({'type': type, 'payload': payload});
  }

  // Client -> Server message factories
  static WsMessage auth({
    required String deviceId,
    String? characterId,
    String? displayName,
    String? location,
  }) {
    return WsMessage(type: 'auth', payload: {
      'device_id': deviceId,
      if (characterId != null) 'character_id': characterId, // ignore: use_null_aware_elements
      if (displayName != null) 'display_name': displayName, // ignore: use_null_aware_elements
      if (location != null) 'location': location, // ignore: use_null_aware_elements
    });
  }

  static WsMessage audio({required String base64Data}) {
    return WsMessage(type: 'audio', payload: {
      'data': base64Data,
      'mime_type': 'audio/pcm;rate=16000',
    });
  }

  static WsMessage text({required String text}) {
    return WsMessage(type: 'text', payload: {'text': text});
  }

  static WsMessage control({required String action}) {
    return WsMessage(type: 'control', payload: {'action': action});
  }
}
