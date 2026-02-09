import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../providers/user_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Wait for device ID to initialize
    await ref.read(deviceIdProvider.future);
    // Attempt to fetch user, but navigate regardless
    try {
      await ref.read(userProvider.future);
    } catch (_) {
      // Backend may be unreachable — continue to contacts anyway
    }

    if (mounted) {
      context.go('/contacts');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.smart_toy, size: 80, color: AppTheme.accent),
              SizedBox(height: 24),
              Text(
                'HLAI',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
