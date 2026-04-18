import 'package:flutter/material.dart';

import '../models/local_ai_model.dart';
import '../services/api_inference_service.dart';
import '../services/gemma_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSwitchingModel = false;
  bool _isSavingApiSettings = false;
  late final TextEditingController _geminiKeyController;
  late final TextEditingController _geminiModelController;
  late final TextEditingController _openRouterKeyController;
  late final TextEditingController _openRouterModelController;
  late ApiProvider _apiProvider;

  @override
  void initState() {
    super.initState();
    final apiSettings = ApiInferenceService.instance.settings;
    _apiProvider = apiSettings.provider;
    _geminiKeyController =
        TextEditingController(text: apiSettings.geminiApiKey);
    _geminiModelController =
        TextEditingController(text: apiSettings.geminiModel);
    _openRouterKeyController =
        TextEditingController(text: apiSettings.openRouterApiKey);
    _openRouterModelController =
        TextEditingController(text: apiSettings.openRouterModel);
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _geminiModelController.dispose();
    _openRouterKeyController.dispose();
    _openRouterModelController.dispose();
    super.dispose();
  }

  Future<void> _switchModel(LocalAiModel model) async {
    if (_isSwitchingModel || model.id == GemmaService.instance.selectedModel.id) {
      return;
    }

    setState(() => _isSwitchingModel = true);
    await GemmaService.instance.selectModel(model.id);
    if (!mounted) {
      return;
    }
    setState(() => _isSwitchingModel = false);
  }

  Future<void> _saveApiSettings() async {
    setState(() => _isSavingApiSettings = true);
    await ApiInferenceService.instance.saveSettings(
      ApiChatSettings(
        provider: _apiProvider,
        geminiApiKey: _geminiKeyController.text.trim(),
        geminiModel: _geminiModelController.text.trim().isEmpty
            ? 'gemini-2.5-flash'
            : _geminiModelController.text.trim(),
        openRouterApiKey: _openRouterKeyController.text.trim(),
        openRouterModel: _openRouterModelController.text.trim().isEmpty
            ? 'google/gemma-4-26b-a4b-it:free'
            : _openRouterModelController.text.trim(),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSavingApiSettings = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API chat settings saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.surface,
      ),
      body: StreamBuilder<LocalAiModel>(
        stream: GemmaService.instance.selectedModelStream,
        initialData: GemmaService.instance.selectedModel,
        builder: (context, modelSnapshot) {
          final selectedModel =
              modelSnapshot.data ?? GemmaService.instance.selectedModel;
          return StreamBuilder<GemmaStatus>(
            stream: GemmaService.instance.statusStream,
            initialData: GemmaService.instance.status,
            builder: (context, statusSnapshot) {
              final status = statusSnapshot.data ?? GemmaStatus.uninitialized;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _StatusCard(
                    model: selectedModel,
                    status: status,
                    errorText: GemmaService.instance.lastErrorMessage,
                    isSwitching: _isSwitchingModel,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    GemmaService.instance.availableModels.length == 1
                        ? 'Bundled Local Model'
                        : 'Local AI Model',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...GemmaService.instance.availableModels.map(
                    (model) => _ModelTile(
                      model: model,
                      isSelected: model.id == selectedModel.id,
                      enabled: !_isSwitchingModel &&
                          GemmaService.instance.availableModels.length > 1,
                      onTap: () => _switchModel(model),
                    ),
                  ),
                  if (GemmaService.instance.availableModels.length == 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        'This build only includes one local model, so there is nothing to switch here.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'API Chat',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Text-only, separate room, short rolling context. Reminder actions still execute locally.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<ApiProvider>(
                          initialValue: _apiProvider,
                          dropdownColor: AppColors.card,
                          decoration: _inputDecoration('Provider'),
                          items: const [
                            DropdownMenuItem(
                              value: ApiProvider.gemini,
                              child: Text('Gemini'),
                            ),
                            DropdownMenuItem(
                              value: ApiProvider.openRouter,
                              child: Text('OpenRouter'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => _apiProvider = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildApiProviderFields(),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _isSavingApiSettings ? null : _saveApiSettings,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                          ),
                          child: Text(
                            _isSavingApiSettings
                                ? 'Saving...'
                                : 'Save API Chat Settings',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildApiProviderFields() {
    if (_apiProvider == ApiProvider.gemini) {
      return Column(
        children: [
          TextField(
            controller: _geminiKeyController,
            obscureText: true,
            decoration: _inputDecoration('Gemini API Key'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _geminiModelController,
            decoration: _inputDecoration('Gemini Model'),
          ),
        ],
      );
    }

    return Column(
      children: [
        TextField(
          controller: _openRouterKeyController,
          obscureText: true,
          decoration: _inputDecoration('OpenRouter API Key'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _openRouterModelController,
          decoration: _inputDecoration('OpenRouter Model'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.model,
    required this.status,
    required this.errorText,
    required this.isSwitching,
  });

  final LocalAiModel model;
  final GemmaStatus status;
  final String? errorText;
  final bool isSwitching;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (status) {
      GemmaStatus.ready => 'Ready',
      GemmaStatus.loading => 'Loading',
      GemmaStatus.error => 'Failed',
      GemmaStatus.unavailable => 'Unavailable',
      GemmaStatus.uninitialized => 'Not loaded',
      _ => 'Preparing',
    };

    final helperText =
        isSwitching ? 'Switching model now.' : errorText ?? model.note;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  model.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  color: status == GemmaStatus.error
                      ? AppColors.danger
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            helperText,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final LocalAiModel model;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? AppColors.accent.withAlpha(110) : Colors.white10,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.note,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
