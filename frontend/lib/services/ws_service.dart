import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../models/ws_message.dart';

enum WsConnectionState { disconnected, connecting, authenticating, connected }

class WsService {
  WebSocketChannel? _channel;
  WsConnectionState _state = WsConnectionState.disconnected;
  String? userId;
  String? sessionId;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WsConnectionState>.broadcast();

  WsConnectionState get state => _state;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsConnectionState> get stateStream => _stateController.stream;

  void _setState(WsConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> connect({
    required String deviceId,
    String? characterId,
    String? displayName,
    String? location,
  }) async {
    if (_state != WsConnectionState.disconnected) return;

    _setState(WsConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConstants.wsUrl));
      await _channel!.ready;

      _setState(WsConnectionState.authenticating);

      // Send auth message
      _channel!.sink.add(
        WsMessage.auth(
          deviceId: deviceId,
          characterId: characterId,
          displayName: displayName,
          location: location,
        ).toJson(),
      );

      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: _onError,
      );
    } catch (e) {
      _setState(WsConnectionState.disconnected);
      _messageController.add({
        'type': 'error',
        'payload': {'message': 'Connection failed: $e'},
      });
    }
  }

  void _onMessage(dynamic data) {
    try {
      final msg = WsMessage.fromJson(data as String);

      switch (msg.type) {
        case 'auth_ok':
          userId = msg.payload['user_id'] as String?;
          sessionId = msg.payload['session_id'] as String?;
          _setState(WsConnectionState.connected);

        default:
          break;
      }

      // Forward all messages to the stream
      _messageController.add({'type': msg.type, 'payload': msg.payload});
    } catch (e) {
      debugPrint('Error processing WS message: $e');
    }
  }

  void sendAudio(Uint8List audioBytes) {
    if (_state != WsConnectionState.connected) return;
    final b64 = base64Encode(audioBytes);
    _channel?.sink.add(WsMessage.audio(base64Data: b64).toJson());
  }

  void sendText(String text) {
    if (_state != WsConnectionState.connected) return;
    _channel?.sink.add(WsMessage.text(text: text).toJson());
  }

  void endSession() {
    _channel?.sink.add(WsMessage.control(action: 'end_session').toJson());
  }

  void _onDisconnected() {
    _setState(WsConnectionState.disconnected);
    _channel = null;
  }

  void _onError(dynamic error) {
    _messageController.add({
      'type': 'error',
      'payload': {'message': 'WebSocket error: $error'},
    });
    _onDisconnected();
  }

  Future<void> disconnect() async {
    endSession();
    await _channel?.sink.close();
    _onDisconnected();
  }

  void dispose() {
    _messageController.close();
    _stateController.close();
    _channel?.sink.close();
  }
}
