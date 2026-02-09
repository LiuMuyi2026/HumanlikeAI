import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/constants.dart';
import '../../config/responsive.dart';
import '../../config/theme.dart';
import '../../providers/character_provider.dart';
import '../../widgets/form_fields/mbti_picker.dart';
import '../../widgets/form_fields/personality_chips.dart';
import '../../widgets/form_fields/familiarity_slider.dart';
import '../../widgets/form_fields/political_slider.dart';
import '../../widgets/form_fields/skills_chips.dart';

class CharacterCreateScreen extends ConsumerStatefulWidget {
  const CharacterCreateScreen({super.key});

  @override
  ConsumerState<CharacterCreateScreen> createState() =>
      _CharacterCreateScreenState();
}

class _CharacterCreateScreenState extends ConsumerState<CharacterCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _regionController = TextEditingController();
  final _occupationController = TextEditingController();
  final _customGenderController = TextEditingController();

  String? _gender;
  String? _mbti;
  List<String> _personalityTraits = [];
  List<String> _skills = [];
  String? _relationshipType;
  int _familiarityLevel = 5;
  String? _politicalLeaning;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    _occupationController.dispose();
    _customGenderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final resolvedGender = _gender == 'Custom'
          ? _customGenderController.text.trim()
          : _gender;

      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        if (resolvedGender != null && resolvedGender.isNotEmpty)
          'gender': resolvedGender,
        if (_regionController.text.trim().isNotEmpty)
          'region': _regionController.text.trim(),
        if (_occupationController.text.trim().isNotEmpty)
          'occupation': _occupationController.text.trim(),
        if (_personalityTraits.isNotEmpty)
          'personality_traits': _personalityTraits,
        if (_mbti != null) 'mbti': _mbti,
        if (_politicalLeaning != null) 'political_leaning': _politicalLeaning,
        if (_relationshipType != null) 'relationship_type': _relationshipType,
        'familiarity_level': _familiarityLevel,
        if (_skills.isNotEmpty) 'skills': _skills,
      };

      final character =
          await ref.read(charactersProvider.notifier).create(body);

      if (mounted) {
        context.go('/character/${character.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Character'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Responsive.constrain(
        context,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: Responsive.contentPadding(context).copyWith(top: 20, bottom: 20),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'Give your character a name',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            // Gender dropdown
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              dropdownColor: AppTheme.surfaceLight,
              items: AppConstants.genderOptions
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _gender = v),
            ),
            if (_gender == 'Custom') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customGenderController,
                decoration: const InputDecoration(
                  labelText: 'Custom Gender',
                  hintText: 'Enter gender identity',
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Region
            TextFormField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: 'Region',
                hintText: 'e.g. Tokyo, New York, London',
              ),
            ),
            const SizedBox(height: 16),

            // Occupation
            TextFormField(
              controller: _occupationController,
              decoration: const InputDecoration(
                labelText: 'Occupation',
                hintText: 'e.g. Artist, Engineer, Student',
              ),
            ),
            const SizedBox(height: 24),

            // Relationship type
            const Text(
              'Relationship Type',
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
              children: AppConstants.relationshipTypes.map((type) {
                final isSelected = _relationshipType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (v) {
                    setState(() {
                      _relationshipType = v ? type : null;
                    });
                  },
                  selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                  backgroundColor: AppTheme.surfaceLight,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // MBTI
            MbtiPicker(
              selected: _mbti,
              onChanged: (v) => setState(() => _mbti = v),
            ),
            const SizedBox(height: 24),

            // Personality traits
            PersonalityChips(
              selected: _personalityTraits,
              onChanged: (v) => setState(() => _personalityTraits = v),
            ),
            const SizedBox(height: 24),

            // Skills
            SkillsChips(
              selected: _skills,
              onChanged: (v) => setState(() => _skills = v),
            ),
            const SizedBox(height: 24),

            // Familiarity
            FamiliaritySlider(
              value: _familiarityLevel,
              onChanged: (v) => setState(() => _familiarityLevel = v),
            ),
            const SizedBox(height: 24),

            // Political leaning slider
            PoliticalSlider(
              value: _politicalLeaning,
              onChanged: (v) => setState(() => _politicalLeaning = v),
            ),
            const SizedBox(height: 32),

            // Save
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Character',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      ),
    );
  }
}
