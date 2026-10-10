import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audio engine for the game. A dedicated looping player handles the BGM while
/// every one-shot SFX gets its own short-lived player, so they mix together.
///
/// The [AudioContext] is configured with `AndroidAudioFocus.none` and
/// `mixWithOthers` so the BGM is never paused/ducked when a sound effect plays.
class GameAudio {
  GameAudio._();

  static final GameAudio instance = GameAudio._();

  static const _mutedKey = 'cubewombat.muted';

  // Created on first use so nothing touches the audio plugin while muted.
  late final AudioPlayer _bgmPlayer = AudioPlayer();
  Future<void>? _configured;

  /// Whether all game audio is muted. Persisted across launches.
  final ValueNotifier<bool> muted = ValueNotifier(false);
  bool _bgmStarted = false;
  String? _playingBgm;

  /// The track the game wants playing, kept while muted so unmuting resumes it.
  String _desiredBgm = 'bgm.mp3';

  double sfxVolume = 0.6;
  double bgmVolume = 0.35;

  bool get _enabled => !muted.value;

  AudioContext _audioContext() => AudioContext(
    android: AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const <AVAudioSessionOptions>{
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );

  /// Restore the saved mute setting. Call once before the first screen.
  Future<void> loadSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      muted.value = preferences.getBool(_mutedKey) ?? false;
    } catch (_) {
      // Settings are optional; fall back to sound on.
    }
  }

  /// (Re)start the background track once the game is allowed to make sound
  /// (safe to call again after every gesture).
  void unlock() {
    if (_enabled && !_bgmStarted) unawaited(_startBgm(_desiredBgm));
  }

  Future<void> init() => _configured ??= _configure();

  Future<void> _configure() async {
    try {
      await _bgmPlayer.setAudioContext(_audioContext());
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(bgmVolume);
    } catch (_) {
      // Audio is optional and should never interrupt gameplay.
    }
  }

  Future<void> _startBgm(String track) async {
    if (_playingBgm == track) return;
    _bgmStarted = true;
    await init();
    try {
      await _bgmPlayer.stop();
      await _bgmPlayer.play(AssetSource('audio/$track'), volume: bgmVolume);
      _playingBgm = track;
    } catch (_) {
      _bgmStarted = false;
    }
  }

  /// Swap (and loop) the background music track. SFX keep playing on top.
  Future<void> startBgm(String name) async {
    _desiredBgm = name;
    if (!_enabled) return;
    await _startBgm(name);
  }

  Future<void> stopBgm() async {
    if (_configured == null) return;
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
    _playingBgm = null;
    _bgmStarted = false;
  }

  /// Pause the BGM while the app is in the background.
  Future<void> pauseBgm() async {
    if (_configured == null) return;
    try {
      await _bgmPlayer.pause();
    } catch (_) {}
  }

  Future<void> resumeBgm() async {
    if (!_enabled || _playingBgm == null) return;
    try {
      await _bgmPlayer.resume();
    } catch (_) {}
  }

  /// One reusable pool per SFX file. Creating a fresh native player for every
  /// jump/land/shield sound causes frame drops, especially on Android.
  final Map<String, Future<AudioPool>> _pools = {};

  Future<void> _play(String filename, {double volumeScale = 1}) async {
    if (!_enabled) return;
    try {
      final pool = await (_pools[filename] ??= AudioPool.create(
        source: AssetSource('audio/$filename'),
        maxPlayers: 3,
        audioContext: _audioContext(),
      ));
      await pool.start(
        volume: (sfxVolume * volumeScale).clamp(0, 1).toDouble(),
      );
    } catch (_) {
      // Audio is optional and should never interrupt gameplay.
      _pools.remove(filename);
    }
  }

  /// Fire-and-forget sound effect. [name] already includes the extension,
  /// e.g. `GameAudio.instance.play('jump.mp3')`.
  Future<void> play(String name, {double volumeScale = 1}) async =>
      _play(name, volumeScale: volumeScale);

  Future<void> setMuted(bool value) async {
    muted.value = value;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_mutedKey, value);
    } catch (_) {}
    if (value) {
      await stopBgm();
    } else {
      await _startBgm(_desiredBgm);
    }
  }

  Future<void> toggleMuted() => setMuted(!muted.value);

  void dispose() {
    if (_configured != null) _bgmPlayer.dispose();
  }
}
