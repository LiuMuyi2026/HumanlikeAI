import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/splash_screen.dart';
import '../screens/contacts/contacts_screen.dart';
import '../screens/character/character_create_screen.dart';
import '../screens/character/character_detail_screen.dart';
import '../screens/character/character_edit_screen.dart';
import '../screens/character/avatar_gallery_screen.dart';
import '../screens/chat/call_screen.dart';
import '../screens/chat/conversation_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/contacts',
      builder: (context, state) => const ContactsScreen(),
    ),
    GoRoute(
      path: '/character/create',
      builder: (context, state) => const CharacterCreateScreen(),
    ),
    GoRoute(
      path: '/character/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return CharacterDetailScreen(characterId: id);
      },
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return CharacterEditScreen(characterId: id);
          },
        ),
        GoRoute(
          path: 'gallery',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return AvatarGalleryScreen(characterId: id);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/conversation/:characterId',
      builder: (context, state) {
        final characterId = state.pathParameters['characterId']!;
        return ConversationScreen(characterId: characterId);
      },
    ),
    GoRoute(
      path: '/call/:characterId',
      pageBuilder: (context, state) {
        final characterId = state.pathParameters['characterId']!;
        final mode = state.uri.queryParameters['mode'] ?? 'voice';
        return MaterialPage(
          fullscreenDialog: true,
          child: CallScreen(characterId: characterId, mode: mode),
        );
      },
    ),
  ],
);
