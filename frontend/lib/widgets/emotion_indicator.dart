import 'package:flutter/material.dart';

import '../config/theme.dart';

class EmotionIndicator extends StatelessWidget {
  final String emotion;

  const EmotionIndicator({super.key, required this.emotion});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _emotionData(emotion);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(emotion),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static (Color, String) _emotionData(String emotion) {
    return switch (emotion) {
      'happy' => (Colors.amber, 'Happy'),
      'sad' => (Colors.blue, 'Sad'),
      'angry' => (Colors.red, 'Angry'),
      'excited' => (Colors.orange, 'Excited'),
      'thinking' => (AppTheme.primary, 'Thinking'),
      'surprised' => (Colors.purple, 'Surprised'),
      'loving' => (AppTheme.accent, 'Loving'),
      'anxious' => (Colors.teal, 'Anxious'),
      'jealous' => (Colors.deepOrange, 'Jealous'),
      'shy' => (Colors.pink, 'Shy'),
      'disappointed' => (Colors.blueGrey, 'Disappointed'),
      'frustrated' => (const Color(0xFFE65100), 'Frustrated'),
      'proud' => (const Color(0xFFFFD600), 'Proud'),
      'grateful' => (Colors.green, 'Grateful'),
      'bored' => (Colors.grey, 'Bored'),
      'curious' => (Colors.lightBlue, 'Curious'),
      'embarrassed' => (Colors.pink[400]!, 'Embarrassed'),
      'playful' => (Colors.purple[400]!, 'Playful'),
      'lonely' => (Colors.indigo, 'Lonely'),
      'confused' => (Colors.brown, 'Confused'),
      _ => (Colors.grey, 'Neutral'),
    };
  }
}
