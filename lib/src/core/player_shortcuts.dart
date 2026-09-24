/// 播放器键盘快捷键注册表：设置页速查/开关与按键处理共用同一数据源，
/// 新增快捷键只需在这里加条目并在 surface 的按键处理里实现对应动作。
library;

/// 快捷键动作标识；持久化禁用列表存的是 [name] 字符串。
enum PlayerShortcutAction {
  playPause,
  mute,
  speedStep,
  seek10,
  speedBoostHold,
  skip,
  volume,
  jumpPercent,
  jumpStartEnd,
  fullscreen,
  home,
  nextEpisode,
}

enum PlayerShortcutGroup { playback, progress, navigation }

class PlayerShortcutEntry {
  const PlayerShortcutEntry(this.action, this.group, this.keysLabel);

  final PlayerShortcutAction action;
  final PlayerShortcutGroup group;

  /// 展示用键位（不含修饰键细节的紧凑写法，如 "← / → / J / L"）。
  final String keysLabel;
}

const playerShortcutEntries = <PlayerShortcutEntry>[
  PlayerShortcutEntry(PlayerShortcutAction.playPause, PlayerShortcutGroup.playback, 'Space / Enter / K'),
  PlayerShortcutEntry(PlayerShortcutAction.mute, PlayerShortcutGroup.playback, 'M'),
  PlayerShortcutEntry(PlayerShortcutAction.speedStep, PlayerShortcutGroup.playback, '+ / −'),
  PlayerShortcutEntry(PlayerShortcutAction.seek10, PlayerShortcutGroup.progress, '← / → / J / L'),
  PlayerShortcutEntry(PlayerShortcutAction.speedBoostHold, PlayerShortcutGroup.progress, '→ (hold)'),
  PlayerShortcutEntry(PlayerShortcutAction.skip, PlayerShortcutGroup.progress, 'Shift + ← / →'),
  PlayerShortcutEntry(PlayerShortcutAction.volume, PlayerShortcutGroup.progress, '↑ / ↓'),
  PlayerShortcutEntry(PlayerShortcutAction.jumpPercent, PlayerShortcutGroup.progress, '0–9'),
  PlayerShortcutEntry(PlayerShortcutAction.jumpStartEnd, PlayerShortcutGroup.progress, 'Home / End'),
  PlayerShortcutEntry(PlayerShortcutAction.fullscreen, PlayerShortcutGroup.navigation, 'F'),
  PlayerShortcutEntry(PlayerShortcutAction.home, PlayerShortcutGroup.navigation, 'Q'),
  PlayerShortcutEntry(PlayerShortcutAction.nextEpisode, PlayerShortcutGroup.navigation, 'N'),
];
