import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/platform_paths.dart';
import '../../core/settings.dart';
import '../../data/local/download_repository.dart';
import 'settings_card_list.dart';
import 'settings_controller.dart';

class DownloadSettingsPage extends ConsumerWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final speed = settings.downloadSpeedLimitMbps;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
            SettingsCardList(children: [
              SettingsCardItem(title: l10n.downloadPath, subtitle: settings.downloadPath, leading: const Icon(Icons.folder_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => _editDownloadPath(context, settings, controller)),
              SettingsCardItem(title: l10n.exportDownloads, subtitle: l10n.exportDownloadsDescription, leading: const Icon(Icons.drive_folder_upload_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => _exportDownloads(context, ref)),
              SettingsSliderItem(title: l10n.downloadSpeedLimit, subtitle: speed == 0 ? l10n.unlimited : '${speed.toStringAsFixed(1)} MB/s', value: speed, min: 0, max: 20, divisions: 40, label: speed == 0 ? l10n.unlimited : '${speed.toStringAsFixed(1)} MB/s', onChanged: (value) => controller.saveChanges((current) => current.copyWith(downloadSpeedLimitMbps: value))),
              SettingsSliderItem(title: l10n.concurrentDownloads, subtitle: l10n.concurrentDownloadsDescription(settings.concurrentDownloads), value: settings.concurrentDownloads.toDouble(), min: 1, max: 5, divisions: 4, label: '${settings.concurrentDownloads}', onChanged: (value) => controller.saveChanges((current) => current.copyWith(concurrentDownloads: value.round()))),
              SettingsMenuItem<int>(title: l10n.downloadQuality, subtitle: l10n.downloadQualityDescription, leading: const Icon(Icons.high_quality_outlined), value: settings.downloadQuality, options: const [1080, 720, 480], label: (value) => l10n.downloadQualityValue(value), onSelected: (value) => controller.saveChanges((current) => current.copyWith(downloadQuality: value))),
           ]),
        ],
      ),
    );
  }

  Future<void> _editDownloadPath(BuildContext context, AppSettings settings, SettingsController controller) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final path = await resolveDefaultDownloadPath();
      await controller.saveChanges((current) => current.copyWith(downloadPath: path));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.privateDownloadPath)));
      return;
    }
    final path = await showDialog<String>(context: context, builder: (_) => _PathDialog(title: AppLocalizations.of(context)!.downloadPath, initialPath: settings.downloadPath));
    if (path == null) return;
    await controller.saveChanges((current) => current.copyWith(downloadPath: path));
  }

  Future<void> _exportDownloads(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid) {
      final exported = await ref.read(downloadProvider.notifier).exportCompletedWithPicker();
      if (!exported) return;
    } else {
      final path = await FilePicker.platform.getDirectoryPath(dialogTitle: AppLocalizations.of(context)!.exportDownloads);
      if (path == null || path.isEmpty) return;
      await ref.read(downloadProvider.notifier).exportCompleted(path);
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.exportCompleted)));
  }
}

class _PathDialog extends StatefulWidget { const _PathDialog({required this.title, required this.initialPath}); final String title; final String initialPath; @override State<_PathDialog> createState() => _PathDialogState(); }
class _PathDialogState extends State<_PathDialog> { late final _controller = TextEditingController(text: widget.initialPath); @override void dispose() { _controller.dispose(); super.dispose(); } Future<void> _browse() async { final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: widget.title, initialDirectory: _controller.text.trim().isEmpty ? null : _controller.text.trim()); if (selected != null) setState(() => _controller.text = selected); } @override Widget build(BuildContext context) { final l10n = AppLocalizations.of(context)!; return AlertDialog(title: Text(widget.title), content: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _controller, autofocus: true, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: l10n.downloadPath, hintText: platformDownloadPathHint(l10n.defaultDownloadPath)))), const SizedBox(width: 8), IconButton(tooltip: l10n.chooseFolder, onPressed: _browse, icon: const Icon(Icons.folder_open_outlined))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: Text(l10n.save))]); } }
