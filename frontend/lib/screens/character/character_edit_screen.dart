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

class CharacterEditScreen extends ConsumerStatefulWidget {
  final String characterId;

  const CharacterEditScreen({super.key, required this.characterId});

  @override
  ConsumerState<CharacterEditScreen> createState() =>
      _CharacterEditScreenState();
}

class _CharacterEditScreenState extends ConsumerState<CharacterEditScreen> {
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
  bool _loaded = false;

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
        'gender': resolvedGender != null && resolvedGender.isNotEmpty
            ? resolvedGender
            : null,
        'region': _regionController.text.trim().isNotEmpty
            ? _regionController.text.trim()
            : null,
        'occupation': _occupationController.text.trim().isNotEmpty
            ? _occupationController.text.trim()
            : null,
        'personality_traits':
            _personalityTraits.isNotEmpty ? _personalityTraits : null,
        'mbti': _mbti,
        'political_leaning': _politicalLeaning,
        'relationship_type': _relationshipType,
        'familiarity_level': _familiarityLevel,
        'skills': _skills.isNotEmpty ? _skills : null,
      };

      await ref
          .read(charactersProvider.notifier)
          .updateCharacter(widget.characterId, body);

      // Refresh the detail provider
      ref.invalidate(characterDetailProvider(widget.characterId));

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final characterAsync =
        ref.watch(characterDetailProvider(widget.characterId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Character'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: characterAsync.when(
        data: (character) {
          // Populate fields once
          if (!_loaded) {
            _nameController.text = character.name;
            _regionController.text = character.region ?? '';
            _occupationController.text = character.occupation ?? '';
            _mbti = character.mbti;
            _personalityTraits =
                List<String>.from(character.personalityTraits ?? []);
            _skills = List<String>.from(character.skills ?? []);
            _relationshipType = character.relationshipType;
            _familiarityLevel = character.familiarityLevel;
            _politicalLeaning = character.politicalLeaning;

            // Determine gender dropdown value
            final g = character.gender;
            if (g == null || g.isEmpty) {
              _gender = null;
            } else if (AppConstants.genderOptions.contains(g)) {
              _gender = g;
            } else {
              _gender = 'Custom';
              _customGenderController.text = g;
            }

            _loaded = true;
          }

          return Responsive.constrain(
            context,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: Responsive.contentPadding(context).copyWith(top: 20, bottom: 20),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Name is required'
                      : null,
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

                TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(labelText: 'Region'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _occupationController,
                  decoration: const InputDecoration(labelText: 'Occupation'),
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

                MbtiPicker(
                  selected: _mbti,
                  onChanged: (v) => setState(() => _mbti = v),
                ),
                const SizedBox(height: 24),

                PersonalityChips(
                  selected: _personalityTraits,
                  onChanged: (v) => setState(() => _personalityTraits = v),
                ),
                const SizedBox(height: 24),

                SkillsChips(
                  selected: _skills,
                  onChanged: (v) => setState(() => _skills = v),
                ),
                const SizedBox(height: 24),

                FamiliaritySlider(
                  value: _familiarityLevel,
                  onChanged: (v) => setState(() => _familiarityLevel = v),
                ),
                const SizedBox(height: 24),

                PoliticalSlider(
                  value: _politicalLeaning,
                  onChanged: (v) => setState(() => _politicalLeaning = v),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
