import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'settings.dart';
import 'shader_assets.dart';
import 'shader_service.dart';

class ConfiguredMediaKitVideoPlayer extends VideoPlayerPlatform {
  static AppSettings settings = const AppSettings();
  static final ConfiguredMediaKitVideoPlayer _instance = ConfiguredMediaKitVideoPlayer();

  final _players = HashMap<int, Player>();
  final _completers = HashMap<int, Completer<void>>();
  final _videoControllers = HashMap<int, VideoController>();
  final _streamControllers = HashMap<int, StreamController<VideoEvent>>();
  final _streamSubscriptions = HashMap<int, List<StreamSubscription>>();
  int _nextTextureId = 0;

  static void registerWith() {
    VideoPlayerPlatform.instance = _instance;
  }

  @override
  Future<void> init() async {
    final playerIds = _players.keys.toList(growable: false);
    for (final playerId in playerIds) {
      await dispose(playerId);
    }
    _players.clear();
    _completers.clear();
    _videoControllers.clear();
    _streamControllers.clear();
    _streamSubscriptions.clear();
  }

  @override
  Future<void> dispose(int playerId) async {
    final player = _players.remove(playerId);
    final streamController = _streamControllers.remove(playerId);
    final subscriptions = _streamSubscriptions.remove(playerId);
    _videoControllers.remove(playerId);
    final completer = _completers.remove(playerId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    for (final subscription in subscriptions ?? const <StreamSubscription>[]) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    if (streamController != null) {
      try {
        await streamController.close();
      } catch (_) {}
    }
    if (player != null) {
      try {
        await player.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final player = Player();
    int? playerId;
    try {
      final native = player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      await _applyCustomParameters(native, settings);
      final videoController = VideoController(
        player,
        configuration: _videoConfiguration(settings),
      );
      await _applyShaders(native, settings);
      final completer = Completer<void>();
      final streamController = StreamController<VideoEvent>();
      final streamSubscriptions = <StreamSubscription>[];
      playerId = ++_nextTextureId;

      _players[playerId] = player;
      _completers[playerId] = completer;
      _videoControllers[playerId] = videoController;
      _streamControllers[playerId] = streamController;
      _streamSubscriptions[playerId] = streamSubscriptions;

      _initialize(playerId);

      final resource = switch (dataSource.sourceType) {
        DataSourceType.asset => dataSource.package == null
            ? 'asset:///${dataSource.asset}'
            : 'asset:///packages/${dataSource.package}/${dataSource.asset}',
        DataSourceType.network || DataSourceType.file || DataSourceType.contentUri => dataSource.uri!,
      };

      await player.open(
        Media(resource, httpHeaders: dataSource.httpHeaders),
        play: false,
      );
      return playerId;
    } catch (_) {
      if (playerId != null && identical(_players[playerId], player)) {
        await dispose(playerId);
      } else {
        try {
          await player.dispose().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _applyCustomParameters(NativePlayer native, AppSettings settings) async {
    for (final parameter in settings.customParameters) {
      final separator = parameter.indexOf('=');
      if (separator <= 0) continue;
      try {
        await native.setProperty(
          parameter.substring(0, separator).trim(),
          parameter.substring(separator + 1).trim(),
        );
      } catch (_) {}
    }
  }

  Future<void> _applyShaders(NativePlayer native, AppSettings settings) async {
    final embed = settings.videoRenderer == VideoRenderer.mediacodecEmbed;
    if (embed || settings.superResolutionMode == SuperResolutionMode.off) return;
    final shaders = settings.superResolutionMode == SuperResolutionMode.efficiency
        ? mpvAnime4KShadersLite
        : mpvAnime4KShaders;
    final directory = ShaderService.directory?.path;
    if (directory == null) return;
    try {
      await native.waitForVideoControllerInitializationIfAttached;
      await native.command([
        'change-list',
        'glsl-shaders',
        'set',
        buildShadersAbsolutePath(directory, shaders),
      ]);
    } catch (_) {}
  }

  VideoControllerConfiguration _videoConfiguration(AppSettings settings) {
    final embed = settings.videoRenderer == VideoRenderer.mediacodecEmbed;
    final acceleration = embed || settings.hardwareAcceleration;
    return VideoControllerConfiguration(
      vo: settings.videoRenderer.mpvValue,
      enableHardwareAcceleration: acceleration,
      hwdec: embed ? 'mediacodec' : acceleration ? 'auto' : 'no',
    );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (_streamControllers[playerId] == null) {
      throw StateError('VideoPlayer for playerId $playerId is not found, Check if its disposed.');
    }
    return _streamControllers[playerId]!.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    final playlistMode = looping ? PlaylistMode.single : PlaylistMode.none;
    return _players[playerId]?.setPlaylistMode(playlistMode);
  }

  @override
  Future<void> play(int playerId) async {
    return _players[playerId]?.play();
  }

  @override
  Future<void> pause(int playerId) async {
    return _players[playerId]?.pause();
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    return _players[playerId]?.setVolume(volume * 100);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    return _players[playerId]?.seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    final player = _players[playerId];
    if (player == null) return;
    try {
      await player.setRate(speed);
    } catch (_) {}
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return _players[playerId]?.platform?.state.position ?? Duration.zero;
  }

  @override
  Widget buildView(int playerId) {
    if (_videoControllers[playerId] == null) {
      throw StateError('VideoPlayer for playerId $playerId is not found, Check if its disposed.');
    }
    return Video(
      key: ValueKey(_videoControllers[playerId]!),
      controller: _videoControllers[playerId]!,
      wakelock: false,
      controls: NoVideoControls,
      fill: const Color(0x00000000),
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future.value();

  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) => Future.value();

  void _initialize(int playerId) {
    if (_streamSubscriptions[playerId]?.isNotEmpty ?? false) return;

    final player = _players[playerId];
    final completer = _completers[playerId];
    final streamController = _streamControllers[playerId];
    final streamSubscriptions = _streamSubscriptions[playerId];

    if (player == null ||
        completer == null ||
        streamController == null ||
        streamSubscriptions == null) {
      return;
    }

    int? width;
    int? height;
    Duration? duration;

    bool isActive() => identical(_streamControllers[playerId], streamController) &&
        !streamController.isClosed;

    void notify() {
      if (isActive() && !completer.isCompleted) {
        if (width != null && height != null && duration != null) {
          streamController.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              size: Size((width ?? 0) * 1.0, (height ?? 0) * 1.0),
              duration: player.state.duration,
            ),
          );
          completer.complete();
        }
      }
    }

    streamSubscriptions.add(
      player.stream.duration.listen((event) {
        if (event > Duration.zero) {
          duration = event;
          notify();
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.videoParams.listen((event) {
        width = event.dw;
        height = event.dh;
        if ((width ?? 0) > 0 && (height ?? 0) > 0) notify();
      }),
    );
    streamSubscriptions.add(
      player.stream.tracks.listen((event) {
        if (event.video.length == 2 && event.audio.length > 2) {
          width = 0;
          height = 0;
          notify();
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.playing.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate, isPlaying: event));
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.completed.listen((event) async {
        await completer.future;
        if (event && isActive()) {
          streamController.add(VideoEvent(eventType: VideoEventType.completed));
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.buffering.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(
            VideoEvent(eventType: event ? VideoEventType.bufferingStart : VideoEventType.bufferingEnd),
          );
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.buffer.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(
            VideoEvent(
              eventType: VideoEventType.bufferingUpdate,
              buffered: [DurationRange(Duration.zero, event)],
            ),
          );
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.error.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.addError(PlatformException(code: '', message: event));
        }
      }),
    );
  }
}
