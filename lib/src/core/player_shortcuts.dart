/// 播放器键盘快捷键注册表：设置页速查/开关/改键与按键处理共用同一数据源，
/// 新增快捷键只需在这里加条目并在 surface 的按键处理里实现对应动作。
library;

import 'package:flutter/services.dart';

/// 快捷键动作标识；持久化禁用列表与改键映射存的是 [name] 字符串。
enum PlayerShortcutAction {
  playPause,
  mute,
  speedStep,
  seekBack,
  seekForward,
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

  /// 展示用默认键位（如 "← / → / J / L"）。
  final String keysLabel;
}

const playerShortcutEntries = <PlayerShortcutEntry>[
  PlayerShortcutEntry(PlayerShortcutAction.playPause, PlayerShortcutGroup.playback, 'Space / Enter / K'),
  PlayerShortcutEntry(PlayerShortcutAction.mute, PlayerShortcutGroup.playback, 'M'),
  PlayerShortcutEntry(PlayerShortcutAction.speedStep, PlayerShortcutGroup.playback, '+ / −'),
  PlayerShortcutEntry(PlayerShortcutAction.seekBack, PlayerShortcutGroup.progress, '← / J'),
  PlayerShortcutEntry(PlayerShortcutAction.seekForward, PlayerShortcutGroup.progress, '→ / L'),
  PlayerShortcutEntry(PlayerShortcutAction.speedBoostHold, PlayerShortcutGroup.progress, '→ (hold)'),
  PlayerShortcutEntry(PlayerShortcutAction.skip, PlayerShortcutGroup.progress, 'Shift + ← / →'),
  PlayerShortcutEntry(PlayerShortcutAction.volume, PlayerShortcutGroup.progress, '↑ / ↓'),
  PlayerShortcutEntry(PlayerShortcutAction.jumpPercent, PlayerShortcutGroup.progress, '0–9'),
  PlayerShortcutEntry(PlayerShortcutAction.jumpStartEnd, PlayerShortcutGroup.progress, 'Home / End'),
  PlayerShortcutEntry(PlayerShortcutAction.fullscreen, PlayerShortcutGroup.navigation, 'F'),
  PlayerShortcutEntry(PlayerShortcutAction.home, PlayerShortcutGroup.navigation, 'Q'),
  PlayerShortcutEntry(PlayerShortcutAction.nextEpisode, PlayerShortcutGroup.navigation, 'N'),
];

/// 键位绑定：默认主键、固定附加键、改键解析与冲突检测。
/// 改键模型：可改键动作只有一个"主键"，自定义后覆盖默认主键；
/// 固定附加键（如播放暂停的 Enter/K/媒体键）不受改键影响。
class PlayerShortcutBinding {
  const PlayerShortcutBinding._();

  /// 可自定义主键的动作；其余（组合键/成对键）不可改。
  static const remappableActions = <PlayerShortcutAction>{
    PlayerShortcutAction.playPause,
    PlayerShortcutAction.seekBack,
    PlayerShortcutAction.seekForward,
    PlayerShortcutAction.mute,
    PlayerShortcutAction.speedBoostHold,
    PlayerShortcutAction.fullscreen,
    PlayerShortcutAction.home,
    PlayerShortcutAction.nextEpisode,
  };

  /// 改键后覆盖的默认主键。
  static const _defaults = <PlayerShortcutAction, LogicalKeyboardKey>{
    PlayerShortcutAction.playPause: LogicalKeyboardKey.space,
    PlayerShortcutAction.seekBack: LogicalKeyboardKey.arrowLeft,
    PlayerShortcutAction.seekForward: LogicalKeyboardKey.arrowRight,
    PlayerShortcutAction.speedBoostHold: LogicalKeyboardKey.arrowRight,
    PlayerShortcutAction.mute: LogicalKeyboardKey.keyM,
    PlayerShortcutAction.fullscreen: LogicalKeyboardKey.keyF,
    PlayerShortcutAction.home: LogicalKeyboardKey.keyQ,
    PlayerShortcutAction.nextEpisode: LogicalKeyboardKey.keyN,
    // 不可改键动作也注册默认键位，用于冲突检测。
    PlayerShortcutAction.skip: LogicalKeyboardKey.arrowRight,
    PlayerShortcutAction.volume: LogicalKeyboardKey.arrowUp,
    PlayerShortcutAction.speedStep: LogicalKeyboardKey.equal,
    PlayerShortcutAction.jumpPercent: LogicalKeyboardKey.digit5,
    PlayerShortcutAction.jumpStartEnd: LogicalKeyboardKey.home,
  };

  /// 固定附加键：改键不影响这些键继续触发对应动作。
  static const _fixedExtras = <PlayerShortcutAction, List<LogicalKeyboardKey>>{
    PlayerShortcutAction.playPause: [LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.keyK, LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaPlay, LogicalKeyboardKey.mediaPause],
    PlayerShortcutAction.seekBack: [LogicalKeyboardKey.keyJ],
    PlayerShortcutAction.seekForward: [LogicalKeyboardKey.keyL],
  };

  static final _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  static bool isModifier(LogicalKeyboardKey key) => _modifiers.contains(key);

  /// 从持久化映射解析动作的自定义主键（值为 LogicalKeyboardKey.keyId 的字符串）。
  static LogicalKeyboardKey? customKey(Map<String, String> keys, PlayerShortcutAction action) {
    final id = int.tryParse(keys[action.name] ?? '');
    return id == null ? null : LogicalKeyboardKey.findKeyByKeyId(id);
  }

  /// 动作当前生效的全部键位（自定义主键或默认主键 + 固定附加键）。
  static List<LogicalKeyboardKey> effectiveKeys(Map<String, String> keys, PlayerShortcutAction action) {
    final custom = customKey(keys, action);
    return [
      if (custom != null) custom else if (_defaults[action] case final fallback?) fallback,
      ...?_fixedExtras[action],
    ];
  }

  /// 冲突检测：返回已占用 [key] 的其他动作（无冲突返回 null）。
  static PlayerShortcutAction? findConflict(Map<String, String> keys, PlayerShortcutAction target, LogicalKeyboardKey key) {
    for (final entry in playerShortcutEntries) {
      if (entry.action == target) continue;
      if (effectiveKeys(keys, entry.action).contains(key)) return entry.action;
    }
    return null;
  }
}
