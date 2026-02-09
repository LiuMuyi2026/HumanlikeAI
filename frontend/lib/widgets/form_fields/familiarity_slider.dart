import 'package:flutter/material.dart';

import '../../config/theme.dart';

class FamiliaritySlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const FamiliaritySlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Familiarity Level',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$value / 10',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Stranger',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: AppTheme.primary,
                inactiveColor: AppTheme.surfaceLight,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            Text(
              'Closest',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
