import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';

class PoliticalSlider extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const PoliticalSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<PoliticalSlider> createState() => _PoliticalSliderState();
}

class _PoliticalSliderState extends State<PoliticalSlider> {
  late bool _cares;
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _cares = widget.value != null && widget.value != 'Not Political';
    _sliderValue = _cares ? _labelToValue(widget.value!) : 2;
  }

  double _labelToValue(String label) {
    final idx = AppConstants.politicalLabels.indexOf(label);
    return idx >= 0 ? idx.toDouble() : 2;
  }

  String _valueToLabel(double value) {
    return AppConstants.politicalLabels[value.round()];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Political Leaning',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
            Row(
              children: [
                Text(
                  'Cares about politics',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _cares,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() => _cares = v);
                    widget.onChanged(v ? _valueToLabel(_sliderValue) : 'Not Political');
                  },
                ),
              ],
            ),
          ],
        ),
        if (_cares) ...[
          const SizedBox(height: 8),
          Slider(
            value: _sliderValue,
            min: 0,
            max: 4,
            divisions: 4,
            activeColor: AppTheme.primary,
            inactiveColor: AppTheme.surfaceLight,
            label: _valueToLabel(_sliderValue),
            onChanged: (v) {
              setState(() => _sliderValue = v);
              widget.onChanged(_valueToLabel(v));
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: AppConstants.politicalLabels
                  .map((l) => Text(
                        l.split(' ').last,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}
