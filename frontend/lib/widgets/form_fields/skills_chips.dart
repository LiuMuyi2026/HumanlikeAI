import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';

class SkillsChips extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const SkillsChips({
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
          'Skills',
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
          children: AppConstants.skills.map((skill) {
            final isSelected = selected.contains(skill);
            return FilterChip(
              label: Text(skill),
              selected: isSelected,
              onSelected: (value) {
                final updated = List<String>.from(selected);
                if (value) {
                  updated.add(skill);
                } else {
                  updated.remove(skill);
                }
                onChanged(updated);
              },
              selectedColor: AppTheme.accent.withValues(alpha: 0.3),
              checkmarkColor: AppTheme.accent,
              backgroundColor: AppTheme.surfaceLight,
              side: BorderSide(
                color: isSelected
                    ? AppTheme.accent
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
