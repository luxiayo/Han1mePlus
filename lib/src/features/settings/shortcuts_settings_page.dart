import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/player_shortcuts.dart';
import '../../core/settings.dart';
import 'settings_card_list.dart';
import 'settings_controller.dart';

class ShortcutsSettingsPage extends ConsumerWidget {
  const ShortcutsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final controller = ref.read(settingsProvider.notifier);
    final disabled = settings.disabledShortcuts;

    String description(PlayerShortcutAction action) => switch (action) {
          PlayerShortcutAction.playPause => l10n.shortcutPlayPause,
          PlayerShortcutAction.mute => l10n.shortcutMute,
          PlayerShortcutAction.speedStep => l10n.shortcutSpeedStep,
          PlayerShortcutAction.seekBack => l10n.shortcutSeekBack,
          PlayerShortcutAction.seekForward => l10n.shortcutSeekForward,
          PlayerShortcutAction.speedBoostHold => l10n.shortcutSpeedBoostHold,
          PlayerShortcutAction.skip => l10n.shortcutSkip,
          PlayerShortcutAction.volume => l10n.shortcutVolume,
          PlayerShortcutAction.jumpPercent => l10n.shortcutJumpPercent,
          PlayerShortcutAction.jumpStartEnd => l10n.shortcutJumpStartEnd,
          PlayerShortcutAction.fullscreen => l10n.shortcutFullscreen,
          PlayerShortcutAction.home => l10n.shortcutHome,
          PlayerShortcutAction.nextEpisode => l10n.shortcutNextEpisode,
        };

    String groupName(PlayerShortcutGroup group) => switch (group) {
          PlayerShortcutGroup.playback => l10n.shortcutGroupPlayback,
          PlayerShortcutGroup.progress => l10n.shortcutGroupProgress,
          PlayerShortcutGroup.navigation => l10n.shortcutGroupNavigation,
        };

    Future<void> toggle(PlayerShortcutAction action, bool value) => controller.saveChanges((current) {
          final next = {...current.disabledShortcuts};
          value ? next.remove(action.name) : next.add(action.name);
          return current.copyWith(disabledShortcuts: next.toList(growable: false));
        });

    Widget entryRow(PlayerShortcutEntry entry) {
      final enabled = !disabled.contains(entry.action.name);
      final remappable = PlayerShortcutBinding.remappableActions.contains(entry.action);
      final customKey = PlayerShortcutBinding.customKey(settings.shortcutKeys, entry.action);
      return SettingsCardItem(
        title: description(entry.action),
        subtitle: customKey != null ? customKey.keyLabel : entry.keysLabel,
        onTap: remappable ? () => _remapDialog(context, ref, entry.action, description) : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (remappable) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Switch(value: enabled, onChanged: (value) => toggle(entry.action, value)),
        ]),
      );
    }

    final groups = PlayerShortcutGroup.values.map((group) {
      final entries = playerShortcutEntries.where((entry) => entry.group == group).toList(growable: false);
      return SettingsCardList(title: groupName(group), children: [for (final entry in entries) entryRow(entry)]);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shortcutsSettings)),
      body: ListView(children: [
        SettingsCardList(title: l10n.shortcutsSettings, children: [
          SettingsCardItem(
            title: l10n.shortcutMasterToggle,
            subtitle: l10n.shortcutMasterSubtitle,
            trailing: Switch(value: settings.keyboardShortcutsEnabled, onChanged: (value) => controller.saveChanges((current) => current.copyWith(keyboardShortcutsEnabled: value))),
          ),
        ]),
        ...groups,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Text(l10n.shortcutFooter, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
    );
  }

  Future<void> _remapDialog(BuildContext context, WidgetRef ref, PlayerShortcutAction action, String Function(PlayerShortcutAction) description) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _KeyCaptureDialog(action: action, description: description),
    );
  }
}

class _KeyCaptureDialog extends ConsumerStatefulWidget {
  const _KeyCaptureDialog({required this.action, required this.description});

  final PlayerShortcutAction action;
  final String Function(PlayerShortcutAction) description;

  @override
  ConsumerState<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends ConsumerState<_KeyCaptureDialog> {
  String? _message;

  Future<void> _save(LogicalKeyboardKey key) async {
    final custom = PlayerShortcutBinding.customKey(ref.read(settingsProvider).valueOrNull?.shortcutKeys ?? const {}, widget.action);
    if (custom == key) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(shortcutKeys: {...current.shortcutKeys, widget.action.name: key.keyId.toString()}));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final custom = PlayerShortcutBinding.customKey(settings.shortcutKeys, widget.action);
    return AlertDialog(
      title: Text(widget.description(widget.action)),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (PlayerShortcutBinding.isModifier(key)) {
            setState(() => _message = l10n.shortcutModifierHint);
            return KeyEventResult.handled;
          }
          final conflict = PlayerShortcutBinding.findConflict(settings.shortcutKeys, widget.action, key);
          if (conflict != null) {
            setState(() => _message = l10n.shortcutConflictWith(key.keyLabel, widget.description(conflict)));
            return KeyEventResult.handled;
          }
          _save(key);
          return KeyEventResult.handled;
        },
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l10n.shortcutCurrentBinding}: ${custom?.keyLabel ?? l10n.shortcutDefaultBinding}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(l10n.shortcutPressKey, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l10n.shortcutEscCancel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        if (custom != null)
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(settingsProvider.notifier).saveChanges((current) {
                final next = {...current.shortcutKeys}..remove(widget.action.name);
                return current.copyWith(shortcutKeys: next);
              });
              if (mounted) navigator.pop();
            },
            child: Text(l10n.shortcutResetDefault),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
      ],
    );
  }
}
