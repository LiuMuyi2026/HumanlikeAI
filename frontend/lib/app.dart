import 'package:flutter/material.dart';

import 'config/theme.dart';
import 'router/app_router.dart';

class HLAIApp extends StatelessWidget {
  const HLAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HLAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
