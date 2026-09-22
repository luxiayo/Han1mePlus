import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/desktop_platform.dart';
import '../../core/playback_speed_policy.dart';
import '../../core/platform_service.dart';
import '../../core/settings.dart';
import '../../core/video_player_shutdown.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import 'video_player_controls.dart';

class VideoPlayerSurface extends ConsumerStatefulWidget {
  const VideoPlayerSurface({required this.controller, required this.quality, required this.video, required this.fullscreen, required this.onFullscreen, required this.onQualitySelected, required this.onSuperResolutionSelected, this.onBack, this.onHome, this.onNext, this.onEpisodeSelected, this.keyframes = const [], this.onKeyframes, this.onAddKeyframe, super.key});
  final ValueListenable<VideoPlayerController?> controller;
  final ValueListenable<String?> quality;
  final VideoDetail video;
  final bool fullscreen;
  final Future<void> Function() onFullscreen;
  final ValueChanged<VideoSource> onQualitySelected;
  final ValueChanged<SuperResolutionMode> onSuperResolutionSelected;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final List<int> keyframes;
  final VoidCallback? onKeyframes;
  final VoidCallback? onAddKeyframe;

  @override
  ConsumerState<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends ConsumerState<VideoPlayerSurface> {
  static const _keyboardSeekStep = Duration(seconds: 10);
  static const _keyboardVolumeStep = 0.1;
  bool _showControls = true;
  bool _locked = false;
  double? _dragStartX;
  _DragDirection? _dragDirection;
  Duration? _seekStartPosition;
  Duration? _dragTargetPosition;
  DateTime _lastDragSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _dragTotalDx = 0;
  double _brightness = 1;
  double _volume = 1;
  _Adjustment? _adjustment;
  Timer? _hideTimer;
  Timer? _adjustmentClearTimer;
  Timer? _speedBoostTimer;
  double? _speedBeforeKeyBoost;
  double? _speedBeforeLongPress;
  int _speedRampToken = 0;

  @override
  void initState() {
    super.initState();
    _readLevels();
    unawaited(PlaybackSpeedPolicy.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartTimer());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _adjustmentClearTimer?.cancel();
    _speedBoostTimer?.cancel();
    super.dispose();
  }

  Future<void> _readLevels() async {
    final levels = await Future.wait([PlatformService.screenBrightness(), PlatformService.volume()]);
    if (mounted) setState(() { _brightness = levels[0]; _volume = levels[1]; });
  }

  void _restartTimer() {
    _hideTimer?.cancel();
    if (!_showControls || _locked) return;
    final seconds = ref.read(settingsProvider).valueOrNull?.playerControlsTimeoutSeconds ?? 4;
    _hideTimer = Timer(Duration(seconds: seconds), () { if (mounted) setState(() => _showControls = false); });
  }

  void _toggleControls() { if (_locked) return; setState(() => _showControls = !_showControls); _restartTimer(); }
  void _togglePlayback() {
    final controller = widget.controller.value;
    if (controller == null) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
    _restartTimer();
  }

  void _handleMouseHover() {
    if (_locked) return;
    if (!_showControls) setState(() => _showControls = true);
    _restartTimer();
  }

  void _showAdjustment(_Adjustment adjustment) {
    _adjustmentClearTimer?.cancel();
    setState(() => _adjustment = adjustment);
    _adjustmentClearTimer = Timer(const Duration(milliseconds: 700), () { if (mounted) setState(() => _adjustment = null); });
  }

  Future<void> _applyVolume(VideoPlayerController controller, double value) async {
    try {
      if (isDesktopHttpPlatform) {
        await controller.setVolume(value);
      } else {
        await PlatformService.setVolume(value);
      }
    } catch (_) {}
  }

  void _keyboardSeek(VideoPlayerController controller, int direction) {
    final duration = controller.value.duration;
    if (duration == Duration.zero) return;
    final from = controller.value.position.inMilliseconds;
    final target = (from + direction * _keyboardSeekStep.inMilliseconds).clamp(0, duration.inMilliseconds);
    unawaited(controller.seekTo(Duration(milliseconds: target)));
    _showAdjustment(_Adjustment.seek(target - from, Duration(milliseconds: target), duration));
    _restartTimer();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isDesktopHttpPlatform) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight && (_speedBoostTimer != null || _speedBeforeKeyBoost != null)) {
        final wasPending = _speedBoostTimer != null;
        _endKeySpeedBoost();
        final controller = widget.controller.value;
        if (wasPending && controller != null && controller.value.isInitialized) _keyboardSeek(controller, 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_locked) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context?.findAncestorStateOfType<EditableTextState>() != null) return KeyEventResult.ignored;
    final controller = widget.controller.value;
    if (controller == null || !controller.value.isInitialized) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      if (key == LogicalKeyboardKey.arrowRight) {
        if (event is KeyDownEvent) _startKeySpeedBoost(controller);
        return KeyEventResult.handled;
      }
      _keyboardSeek(controller, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? _keyboardVolumeStep : -_keyboardVolumeStep;
      final volume = (_volume + delta).clamp(0.0, 1.0).toDouble();
      _volume = volume;
      unawaited(_applyVolume(controller, volume));
      _showAdjustment(_Adjustment.volume(volume));
      _restartTimer();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.keyF) {
      unawaited(widget.onFullscreen());
      _restartTimer();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.escape && widget.onHome != null) {
      widget.onHome!();
      return KeyEventResult.handled;
    }
    const playbackKeys = [LogicalKeyboardKey.space, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaPlay, LogicalKeyboardKey.mediaPause];
    if (playbackKeys.contains(key)) {
      _togglePlayback();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _startKeySpeedBoost(VideoPlayerController controller) {
    if (_speedBoostTimer != null || _speedBeforeKeyBoost != null) return;
    _speedBoostTimer = Timer(const Duration(milliseconds: 450), () {
      _speedBoostTimer = null;
      if (!mounted || _locked) return;
      final active = widget.controller.value;
      if (active == null || !identical(active, controller) || !active.value.isInitialized || !active.value.isPlaying) return;
      final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      _speedBeforeKeyBoost = active.value.playbackSpeed;
      final speed = PlaybackSpeedPolicy.longPressSpeed(
        settings,
        isThreeDimensional: PlaybackSpeedPolicy.isThreeDimensional(widget.video.genre, widget.video.title),
      );
      unawaited(_applySpeed(active, speed));
      _adjustmentClearTimer?.cancel();
      setState(() => _adjustment = _Adjustment.speed(speed));
    });
  }

  void _endKeySpeedBoost() {
    _speedBoostTimer?.cancel();
    _speedBoostTimer = null;
    final saved = _speedBeforeKeyBoost;
    if (saved == null) return;
    _speedBeforeKeyBoost = null;
    final active = widget.controller.value;
    if (active != null && active.value.isInitialized) unawaited(_applySpeed(active, saved));
    if (mounted) setState(() => _adjustment = null);
  }

  void _longPress(bool active) {
    final controller = widget.controller.value;
    if (active) {
      if (controller == null || !controller.value.isInitialized || _speedBeforeLongPress != null) return;
      final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      _speedBeforeLongPress = controller.value.playbackSpeed;
      final speed = PlaybackSpeedPolicy.longPressSpeed(
        settings,
        isThreeDimensional: PlaybackSpeedPolicy.isThreeDimensional(widget.video.genre, widget.video.title),
      );
      unawaited(_applySpeed(controller, speed));
      setState(() => _adjustment = _Adjustment.speed(speed));
      return;
    }
    if (controller == null) {
      _speedBeforeLongPress = null;
      return;
    }
    final speed = _speedBeforeLongPress ?? controller.value.playbackSpeed;
    _speedBeforeLongPress = null;
    if (!controller.value.isInitialized) return;
    unawaited(_applySpeed(controller, speed));
    setState(() => _adjustment = null);
  }

  Future<void> _applySpeed(VideoPlayerController controller, double speed) async {
    // 令牌取消：快速反复长按时，旧过渡立即让位给新目标倍速。
    final token = ++_speedRampToken;
    try {
      final current = controller.value.playbackSpeed;
      // 大幅变速一步跳变，播放内核按音频时钟重排帧时间轴会产生一次可见的
      // 帧衔接跳变；播放中改为分步过渡，每步的重排小到不可察。
      if (controller.value.isPlaying && (speed - current).abs() >= .5) {
        for (final step in PlaybackSpeedPolicy.rampSteps(current, speed)) {
          if (token != _speedRampToken) return;
          await controller.setPlaybackSpeed(step);
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        if (token != _speedRampToken) return;
      }
      if ((controller.value.playbackSpeed - speed).abs() > .001) {
        await controller.setPlaybackSpeed(speed);
      }
    } catch (_) {}
  }

  void _dragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragDirection = null;
    _seekStartPosition = widget.controller.value?.value.position;
    _dragTargetPosition = _seekStartPosition;
    _lastDragSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
    _dragTotalDx = 0;
  }

  void _dragUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    if (startX == null || _locked) return;
    final controller = widget.controller.value;
    if (controller == null) return;
    final size = context.size ?? MediaQuery.sizeOf(context);
    final direction = _dragDirection ??= details.delta.dx.abs() > details.delta.dy.abs() ? _DragDirection.horizontal : _DragDirection.vertical;
    if (direction == _DragDirection.horizontal) {
      _dragTotalDx += details.delta.dx;
      final duration = controller.value.duration;
      final sensitivity = ref.read(settingsProvider).valueOrNull?.seekSensitivity ?? .35;
      if (duration != Duration.zero) {
        final startMs = _seekStartPosition?.inMilliseconds ?? controller.value.position.inMilliseconds;
        final target = (startMs + (_dragTotalDx / size.width * duration.inMilliseconds * sensitivity)).round().clamp(0, duration.inMilliseconds).toInt();
        _dragTargetPosition = Duration(milliseconds: target);
        setState(() => _adjustment = _Adjustment.seek(target - startMs, Duration(milliseconds: target), duration));
        // 节流 seek 让画面实时更新确认目标帧；进度条通过 seekPreviewPosition 显示目标位置，
        // 不受播放器实际位置变动影响。最终位置在 _dragEnd 补齐。
        final now = DateTime.now();
        if (now.difference(_lastDragSeekAt) >= const Duration(milliseconds: 150)) {
          _lastDragSeekAt = now;
          controller.seekTo(Duration(milliseconds: target));
        }
      }
      return;
    }
    final value = (startX < size.width / 2 ? _brightness : _volume) - details.delta.dy / size.height;
    if (startX < size.width / 2) { _brightness = value.clamp(0.01, 1).toDouble(); PlatformService.setScreenBrightness(_brightness); setState(() => _adjustment = _Adjustment.brightness(_brightness)); }
    else { _volume = value.clamp(0, 1).toDouble(); unawaited(_applyVolume(controller, _volume)); setState(() => _adjustment = _Adjustment.volume(_volume)); }
  }
  void _dragEnd(DragEndDetails details) {
    if (_dragDirection == _DragDirection.horizontal) {
      final target = _dragTargetPosition;
      if (target != null) widget.controller.value?.seekTo(target);
    }
    _dragStartX = null; _dragDirection = null; _seekStartPosition = null; _dragTargetPosition = null; _dragTotalDx = 0;
    // 触发重建让控制栏退出 seekPreview 状态、恢复显示播放器实际位置。
    setState(() {});
    _adjustmentClearTimer?.cancel(); _adjustmentClearTimer = Timer(const Duration(milliseconds: 700), () { if (mounted) setState(() => _adjustment = null); });
  }

  Future<void> _enterPictureInPicture(VideoPlayerController controller) async {
    var entered = false;
    try {
      entered = await PlatformService.enterPictureInPicture();
    } catch (_) {}
    if (entered) VideoPlayerShutdown.pipActive = controller;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: widget.controller,
        builder: (context, activeController, _) {
          final controller = activeController;
          if (controller == null || !controller.value.isInitialized) {
            return const Center(child: M3ELoadingIndicator(color: Colors.white));
          }
          return MouseRegion(
            onHover: (_) => _handleMouseHover(),
            onExit: (_) => _restartTimer(),
            child: _PinchFullscreen(
              onToggle: () => unawaited(widget.onFullscreen()),
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: _togglePlayback,
              onLongPressStart: (_) => _longPress(true),
              onLongPressEnd: (_) => _longPress(false),
              onLongPressCancel: () => _longPress(false),
              onSecondaryLongPressStart: (_) => _longPress(true),
              onSecondaryLongPressEnd: (_) => _longPress(false),
              onSecondaryLongPressCancel: () => _longPress(false),
              onPanStart: _dragStart,
              onPanUpdate: _dragUpdate,
              onPanEnd: _dragEnd,
              child: LayoutBuilder(builder: (context, constraints) {
                final cw = constraints.maxWidth;
                final ch = constraints.maxHeight;
                final vr = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
                // 模拟 _VideoViewport 的居中 aspect-fit，算出视频在容器中的实际位置。
                final vh = cw / ch > vr ? ch : cw / vr;
                final vt = (ch - vh) / 2;
                final vb = vt + vh;
                final isLandscape = cw > ch;
                // 横屏且黑边高度足够放下控制栏时，把控件放入黑边而非覆盖视频。
                final useTopBar = isLandscape && vt >= 44;
                final bottomControls = VideoPlayerControls(controller: controller, fullscreen: widget.fullscreen, onFullscreen: widget.onFullscreen, onInteraction: _restartTimer, video: widget.video, quality: widget.quality, onQualitySelected: widget.onQualitySelected, onSuperResolutionSelected: widget.onSuperResolutionSelected, onNext: widget.onNext, onEpisodeSelected: widget.onEpisodeSelected, seekPreviewPosition: _dragTargetPosition, bottomOffset: isLandscape ? (ch - vb).clamp(0, double.infinity) : 0);
                final backTop = useTopBar ? (vt - 44) / 2 : 8.0;
                final skipTop = useTopBar ? (vt - 44) / 2 : 4.0;
                final titleTop = useTopBar ? (vt - 36) / 2 : 8.0;
                return Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Colors.black),
                _VideoViewport(controller: controller),
                ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) => value.isBuffering ? const Center(child: M3ELoadingIndicator(color: Colors.white)) : const SizedBox.shrink()),
                ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) => _showControls && !_locked ? bottomControls : const SizedBox.shrink()),
                if (_locked) useTopBar ? Positioned(top: backTop, right: 8, child: IconButton(color: Colors.white, tooltip: l10n.unlockControls, onPressed: () { setState(() => _locked = false); _restartTimer(); }, icon: const Icon(Icons.lock))) : Align(alignment: Alignment.centerRight, child: IconButton(color: Colors.white, tooltip: l10n.unlockControls, onPressed: () { setState(() => _locked = false); _restartTimer(); }, icon: const Icon(Icons.lock))),
                if (_showControls && !_locked && widget.onBack != null)
                  Positioned(
                    top: backTop,
                    left: 8,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      BackButton(color: Colors.white, onPressed: widget.onBack),
                      if (widget.onHome != null) IconButton(color: Colors.white, tooltip: l10n.home, onPressed: widget.onHome, icon: const Icon(Icons.home_outlined)),
                    ]),
                  ),
                if (_showControls && widget.fullscreen && !_locked) useTopBar ? Positioned(top: backTop, right: 8, child: IconButton(color: Colors.white, tooltip: l10n.lockControls, onPressed: () => setState(() => _locked = true), icon: const Icon(Icons.lock_open_outlined))) : Align(alignment: Alignment.centerRight, child: IconButton(color: Colors.white, tooltip: l10n.lockControls, onPressed: () => setState(() => _locked = true), icon: const Icon(Icons.lock_open_outlined))),
                if (widget.fullscreen && widget.keyframes.isNotEmpty) _KeyframeCountdown(controller: controller, keyframes: widget.keyframes),
                if (_showControls && widget.fullscreen && !_locked) Positioned(top: titleTop, left: widget.onHome != null ? 96 : 48, right: 212, child: _MarqueeTitle(title: widget.video.title)),
                if (_showControls && !_locked)
                  Positioned(
                    top: skipTop,
                    right: widget.fullscreen && widget.onKeyframes != null ? 56 : 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoPlayerSkipButton(controller: controller, onInteraction: _restartTimer),
                        if (Platform.isAndroid) IconButton(color: Colors.white, tooltip: l10n.pictureInPicture, visualDensity: VisualDensity.compact, onPressed: () => _enterPictureInPicture(controller), icon: const Icon(Icons.picture_in_picture_alt_outlined)),
                        widget.fullscreen
                            ? VideoPlayerFullscreenMoreMenu(sources: widget.video.sources, quality: widget.quality)
                            : VideoPlayerPortraitMoreMenu(controller: controller, video: widget.video, quality: widget.quality, onQualitySelected: widget.onQualitySelected, onSuperResolutionSelected: widget.onSuperResolutionSelected),
                      ],
                    ),
                  ),
                if (_showControls && widget.fullscreen && !_locked && widget.onKeyframes != null)
                  Positioned(
                    top: useTopBar ? backTop : 8,
                    right: 8,
                    child: Tooltip(
                      message: l10n.longPressAddKeyframe,
                      child: GestureDetector(
                        onTap: widget.onKeyframes,
                        onLongPress: widget.onAddKeyframe,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('🥵', style: TextStyle(fontSize: 24)),
                        ),
                      ),
                    ),
                  ),
                if (_adjustment != null)
                  switch (_adjustment!.kind) {
                    _AdjustmentKind.brightness => Positioned(top: 24, left: 16, child: _AdjustmentHud(adjustment: _adjustment!)),
                    _AdjustmentKind.volume => Positioned(top: 24, right: 16, child: _AdjustmentHud(adjustment: _adjustment!)),
                    _ => Positioned(top: 24, left: 0, right: 0, child: Center(child: _AdjustmentHud(adjustment: _adjustment!))),
                  },
              ]);
              }),
            ),
            ),
          );
        },
      ),
    );
  }
}

/// 双指张开进入全屏、捏合退出全屏。包裹在播放器手势外层，
/// 单指拖动/点击等仍由内层 GestureDetector 处理，互不干扰。
class _PinchFullscreen extends StatefulWidget {
  const _PinchFullscreen({required this.onToggle, required this.child});

  final VoidCallback onToggle;
  final Widget child;

  @override
  State<_PinchFullscreen> createState() => _PinchFullscreenState();
}

class _PinchFullscreenState extends State<_PinchFullscreen> {
  bool _active = false;
  bool _triggered = false;

  // 张开超过 12% 触发进入全屏，捏合到 88% 触发退出全屏。
  static const _zoomInThreshold = 1.12;
  static const _zoomOutThreshold = .88;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (details) {
        _active = details.pointerCount >= 2;
        _triggered = false;
      },
      onScaleUpdate: (details) {
        if (!_active || _triggered) return;
        if (details.pointerCount < 2) return;
        // details.scale 从 1.0 起累积：>1 为张开，<1 为捏合。
        if (details.scale >= _zoomInThreshold || details.scale <= _zoomOutThreshold) {
          _triggered = true;
          widget.onToggle();
        }
      },
      onScaleEnd: (_) {
        _active = false;
        _triggered = false;
      },
      child: widget.child,
    );
  }
}

class _VideoViewport extends ConsumerWidget {
  const _VideoViewport({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspect = ref.watch(settingsProvider).valueOrNull?.videoAspectRatio ?? VideoAspectRatio.auto;
    final ratio = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    return switch (aspect) {
      VideoAspectRatio.auto => Center(child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(controller))),
      VideoAspectRatio.ratio4x3 => Center(child: AspectRatio(aspectRatio: 4 / 3, child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller))))),
      VideoAspectRatio.crop => Positioned.fill(child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller)))),
      VideoAspectRatio.stretch => Positioned.fill(child: FittedBox(fit: BoxFit.fill, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller)))),
    };
  }
}

class _MarqueeTitle extends StatefulWidget {
  const _MarqueeTitle({required this.title});
  final String title;

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: (widget.title.length * 85).clamp(4000, 16000).toInt()))..repeat();
  }

  @override
  void didUpdateWidget(_MarqueeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title == widget.title) return;
    _controller
      ..duration = Duration(milliseconds: (widget.title.length * 85).clamp(4000, 16000).toInt())
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        const style = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
        final painter = TextPainter(text: TextSpan(text: widget.title, style: style), maxLines: 1, textDirection: TextDirection.ltr)..layout();
        final width = painter.width;
        final overflows = width > constraints.maxWidth;
        final distance = width - constraints.maxWidth + 24;
        painter.dispose();
        if (!overflows) return Text(widget.title, maxLines: 1, style: style);
        return ClipRect(child: AnimatedBuilder(animation: _controller, builder: (context, child) => Transform.translate(offset: Offset(-distance * _controller.value, 0), child: child), child: Text(widget.title, maxLines: 1, style: style)));
      });
}

enum _DragDirection { horizontal, vertical }
enum _AdjustmentKind { brightness, volume, speed, seek }
class _Adjustment {
  const _Adjustment(this.kind, this.value, {this.delta, this.position, this.duration});
  factory _Adjustment.brightness(double value) => _Adjustment(_AdjustmentKind.brightness, value);
  factory _Adjustment.volume(double value) => _Adjustment(_AdjustmentKind.volume, value);
  factory _Adjustment.speed(double value) => _Adjustment(_AdjustmentKind.speed, value);
  factory _Adjustment.seek(int delta, Duration position, Duration duration) => _Adjustment(_AdjustmentKind.seek, 0, delta: delta, position: position, duration: duration);
  final _AdjustmentKind kind;
  final double value;
  final int? delta;
  final Duration? position;
  final Duration? duration;
}

class _AdjustmentHud extends StatelessWidget {
  const _AdjustmentHud({required this.adjustment});
  final _Adjustment adjustment;

  @override
  Widget build(BuildContext context) => switch (adjustment.kind) {
        _AdjustmentKind.seek => _seekCard(),
        _AdjustmentKind.speed => _pill(Text('${adjustment.value}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        _ => _levelCard(),
      };

  Widget _pill(Widget child) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(999)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: child),
      );

  Widget _seekCard() {
    final delta = adjustment.delta ?? 0;
    final position = adjustment.position ?? Duration.zero;
    final duration = adjustment.duration ?? Duration.zero;
    return _pill(Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(delta >= 0 ? Icons.fast_forward : Icons.fast_rewind, color: Colors.white, size: 28),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${delta >= 0 ? '+' : '-'}${_formatDuration(Duration(milliseconds: delta.abs()))}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${_formatDuration(position)}/${_formatDuration(duration)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]));
  }

  Widget _levelCard() {
    final brightness = adjustment.kind == _AdjustmentKind.brightness;
    final level = adjustment.value.clamp(0, 1).toDouble();
    return _pill(Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 180,
        height: 56,
        child: IgnorePointer(
          child: M3ESlider(
            value: level,
            onChanged: (_) {},
            icon: Icon(brightness ? Icons.brightness_6 : Icons.volume_up, size: 20),
            trailingIcon: false,
            decoration: M3ESliderDecoration(
              trackHeight: 44,
              trackCornerRadius: 22,
              thumbWidth: 6,
              thumbHeight: 56,
              trackIconSize: 20,
              trackIconActiveColor: Colors.white,
              trackIconInactiveColor: Colors.white70,
              colors: M3ESliderColors(
                thumbColor: Colors.white,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                disabledThumbColor: Colors.white,
                disabledActiveTrackColor: Colors.white,
                disabledInactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                activeTickColor: Colors.transparent,
                inactiveTickColor: Colors.transparent,
                disabledActiveTickColor: Colors.transparent,
                disabledInactiveTickColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text('${(level * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ]));
  }
}

class _KeyframeCountdown extends StatelessWidget {
  const _KeyframeCountdown({required this.controller, required this.keyframes});
  final VideoPlayerController controller;
  final List<int> keyframes;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final next = keyframes.where((item) => item >= value.position.inMilliseconds).firstOrNull;
          final remaining = next == null ? null : next - value.position.inMilliseconds;
          if (remaining == null || remaining > 10000) return const SizedBox.shrink();
          return Positioned(left: 16, top: 60, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text(AppLocalizations.of(context)!.keyframeCountdown((remaining / 1000).toStringAsFixed(1)), style: const TextStyle(color: Colors.white)))));
        },
      );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours > 0 ? '${duration.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
