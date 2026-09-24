import 'package:flutter/material.dart';
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
          PlayerShortcutAction.seek10 => l10n.shortcutSeek10,
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

    Widget entryRow(PlayerShortcutEntry entry) {
      final enabled = !disabled.contains(entry.action.name);
      return SettingsCardItem(
        title: description(entry.action),
        subtitle: entry.keysLabel,
        trailing: Switch(
          value: enabled,
          onChanged: (value) => controller.saveChanges((current) {
            final next = {...current.disabledShortcuts};
            value ? next.remove(entry.action.name) : next.add(entry.action.name);
            return current.copyWith(disabledShortcuts: next.toList(growable: false));
          }),
        ),
      );
    }

    final groups = PlayerShortcutGroup.values.map((group) {
      final entries = playerShortcutEntries.where((entry) => entry.group == group).toList(growable: false);
      return SettingsCardList(title: groupName(group), children: [for (final entry in entries) entryRow(entry)]);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shortcutsSettings)),
      body: ListView(children: [
        ...groups,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Text(l10n.shortcutFooter, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
    );
  }
}
