import 'package:flutter_gemma/flutter_gemma.dart';

class LocalAiModel {
  const LocalAiModel({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.modelType,
    required this.note,
  });

  final String id;
  final String label;
  final String assetPath;
  final ModelType modelType;
  final String note;
}
