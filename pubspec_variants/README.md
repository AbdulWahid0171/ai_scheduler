Use one of these files as your active [pubspec.yaml](/D:/flutter_projects/ai_scheduler/pubspec.yaml) before running the app.

Variants:
- `pubspec_1b.yaml`
- `pubspec_2b.yaml`
- `pubspec_deepseek.yaml`

Recommended workflow:
1. Replace the root `pubspec.yaml` with the variant you want to test.
2. Make sure the matching model file exists in `assets/models/`.
3. Run `flutter pub get`.
4. Run `flutter run`.

Expected model files:
- `pubspec_1b.yaml` -> `assets/models/gemma3-1b-it-int4.task`
- `pubspec_2b.yaml` -> `assets/models/Gemma2-2B-IT_multi-prefill-seq_q8_ekv1280.task`
- `pubspec_deepseek.yaml` -> `assets/models/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv1280.task`

Note:
- The DeepSeek variant will not build until that file is present again in `assets/models/`.
