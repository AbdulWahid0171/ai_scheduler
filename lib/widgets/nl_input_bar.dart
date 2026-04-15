import 'package:flutter/material.dart';

import '../services/nl_parser.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class NaturalLanguageInputBar extends StatelessWidget {
  const NaturalLanguageInputBar({
    super.key,
    required this.controller,
    required this.preview,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ParsedReminderInput preview;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Submit report Friday 5pm',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: const Icon(Icons.auto_awesome, color: AppColors.accent),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            preview.title.isEmpty
                ? 'Creating: add a title, then we will preview the parsed date and time here.'
                : 'Creating: ${preview.title} on ${AppDateUtils.formatShortDate(preview.dateTime)} at ${AppDateUtils.formatTime(preview.dateTime)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
