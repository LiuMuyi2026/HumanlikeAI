import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';

class PersonalityChips extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const PersonalityChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personality Traits',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.personalityTraits.map((trait) {
            final isSelected = selected.contains(trait);
            return FilterChip(
              label: Text(trait),
              selected: isSelected,
              onSelected: (value) {
                final updated = List<String>.from(selected);
                if (value) {
                  updated.add(trait);
                } else {
                  updated.remove(trait);
                }
                onChanged(updated);
              },
              selectedColor: AppTheme.primary.withValues(alpha: 0.3),
              checkmarkColor: AppTheme.primary,
              backgroundColor: AppTheme.surfaceLight,
              side: BorderSide(
                color: isSelected
                    ? AppTheme.primary
                    : Colors.white.withValues(alpha: 0.1),
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
