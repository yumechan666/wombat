import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SpriteFrameData {
  const SpriteFrameData({
    required this.source,
    required this.content,
    required this.anchorX,
    required this.anchorY,
  });

  final ui.Rect source;
  final ui.Rect content;
  final double anchorX;
  final double anchorY;

  /// The same frame in an atlas image decoded at [factor] of its size.
  SpriteFrameData scaled(double factor) {
    if (factor == 1) return this;
    ui.Rect scale(ui.Rect rect) => ui.Rect.fromLTWH(
      rect.left * factor,
      rect.top * factor,
      rect.width * factor,
      rect.height * factor,
    );
    return SpriteFrameData(
      source: scale(source),
      content: scale(content),
      anchorX: anchorX * factor,
      anchorY: anchorY * factor,
    );
  }

  factory SpriteFrameData.fromJson(Map<String, dynamic> json) {
    ui.Rect rect(Map<String, dynamic>? value) {
      final data = value ?? const <String, dynamic>{};
      return ui.Rect.fromLTWH(
        (data['x'] as num?)?.toDouble() ?? 0,
        (data['y'] as num?)?.toDouble() ?? 0,
        (data['w'] as num?)?.toDouble() ?? 0,
        (data['h'] as num?)?.toDouble() ?? 0,
      );
    }

    final source = rect(json['source'] as Map<String, dynamic>?);
    final content = rect(json['content'] as Map<String, dynamic>?);
    final anchor = json['anchor'] as Map<String, dynamic>? ?? const {};
    return SpriteFrameData(
      source: source,
      content: content.isEmpty ? source : content,
      anchorX: (anchor['x'] as num?)?.toDouble() ?? source.center.dx,
      anchorY: (anchor['y'] as num?)?.toDouble() ?? source.bottom,
    );
  }
}

class SpriteAtlas {
  SpriteAtlas({
    required this.image,
    required this.frames,
    required this.animations,
  }) : animationHeights = {
         for (final entry in animations.entries)
           if (entry.value.isNotEmpty)
             entry.key: entry.value
                 .map((frame) => frame.content.height)
                 .reduce(math.max),
       };

  final ui.Image image;
  final Map<String, SpriteFrameData> frames;
  final Map<String, List<SpriteFrameData>> animations;
  final Map<String, double> animationHeights;

  SpriteFrameData? frame(String name, [int index = 0]) {
    final animation = animations[name];
    if (animation != null && animation.isNotEmpty) {
      return animation[index % animation.length];
    }
    return frames[name];
  }
}

class GameAssetCatalog {
  GameAssetCatalog._(this.manifest);

  final Map<String, String> manifest;
  final Map<String, SpriteAtlas> _atlases = {};
  final Map<String, Future<void>> _pending = {};

  /// Character sheets are drawn at ~80px but stored as ~1968px atlases.
  /// Decoding them smaller makes loading (e.g. switching skins) much faster
  /// and uses about a third of the memory.
  static double _decodeScale(String key) =>
      key.startsWith('SKIN_') ||
          key.startsWith('MOMO_') ||
          key.startsWith('ENEMY_SHEET') ||
          key.startsWith('RANGED_ENEMY')
      ? 0.6
      : 1;

  static const _skinGroups = <String>[
    'MOVE',
    'AIR',
    'CRAFT',
    'SHIELD',
    'BURROW',
    'DAMAGE',
  ];

  static Future<GameAssetCatalog> load() async {
    final manifest =
        (jsonDecode(
                  await rootBundle.loadString(
                    'assets/json/asset_manifest.json',
                  ),
                )
                as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value.toString()));
    return GameAssetCatalog._(manifest);
  }

  Future<void> loadKeys(Iterable<String> keys) async {
    await Future.wait(keys.map(loadKey));
  }

  Future<void> loadSkin(String prefix) async {
    await loadKeys(_skinGroups.map((group) => 'SKIN_${prefix}_$group'));
  }

  void retainOnly(Set<String> keys) {
    for (final key in _atlases.keys.toList()) {
      if (keys.contains(key)) continue;
      _atlases.remove(key)?.image.dispose();
    }
  }

  bool isLoaded(String key) => _atlases.containsKey(key);

  Future<void> loadKey(String key) {
    if (_atlases.containsKey(key)) return Future.value();
    // Share one decode between concurrent requests for the same atlas.
    // Block body: returning the removed future would make whenComplete wait
    // on itself forever.
    return _pending[key] ??= _loadKey(key).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<void> _loadKey(String key) async {
    final relativeImage = manifest[key];
    if (relativeImage == null) return;
    final imagePath = 'assets/images/${relativeImage.split('/').last}';
    final data = await rootBundle.load(imagePath);
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      data.buffer.asUint8List(),
    );
    final decodeScale = _decodeScale(key);
    var intrinsicWidth = 0;
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        intrinsicWidth = width;
        return ui.TargetImageSize(
          width: (width * decodeScale).round(),
          height: (height * decodeScale).round(),
        );
      },
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final factor = intrinsicWidth == 0 ? 1.0 : image.width / intrinsicWidth;
    final frameFile = relativeImage.endsWith('.webp')
        ? relativeImage.replaceFirst(RegExp(r'\.webp$'), '.frames.json')
        : '';
    final framePath = 'assets/json/${frameFile.split('/').last}';
    Map<String, dynamic> frameJson = const {};
    if (frameFile.isNotEmpty &&
        (relativeImage.contains('transparent') ||
            relativeImage.contains('tiles'))) {
      try {
        frameJson =
            jsonDecode(await rootBundle.loadString(framePath))
                as Map<String, dynamic>;
      } on FlutterError {
        frameJson = const {};
      }
    }
    final frames = <String, SpriteFrameData>{};
    for (final raw in (frameJson['frames'] as List<dynamic>? ?? const [])) {
      final value = Map<String, dynamic>.from(raw as Map);
      frames[value['name'].toString()] = SpriteFrameData.fromJson(
        value,
      ).scaled(factor);
    }
    final animations = <String, List<SpriteFrameData>>{};
    for (final raw in (frameJson['animations'] as List<dynamic>? ?? const [])) {
      final value = Map<String, dynamic>.from(raw as Map);
      animations[value['name'].toString()] = (value['frames'] as List<dynamic>)
          .map(
            (frame) => SpriteFrameData.fromJson(
              Map<String, dynamic>.from(frame as Map),
            ).scaled(factor),
          )
          .toList(growable: false);
    }
    _atlases[key] = SpriteAtlas(
      image: image,
      frames: frames,
      animations: animations,
    );
  }

  SpriteAtlas? operator [](String key) => _atlases[key];

  bool drawInCell(
    ui.Canvas canvas,
    String key,
    String frameName,
    ui.Rect destination, {
    int frameIndex = 0,
    double alpha = 1,
    bool flipX = false,
    bool alignBottom = false,
  }) {
    final atlas = _atlases[key];
    final frame = atlas?.frame(frameName, frameIndex);
    if (atlas == null || frame == null || frame.content.isEmpty) return false;
    final crop = frame.content;
    final scale = math.min(
      destination.width / crop.width,
      destination.height / crop.height,
    );
    final width = crop.width * scale;
    final height = crop.height * scale;
    final target = ui.Rect.fromLTWH(
      destination.left + (destination.width - width) / 2,
      alignBottom
          ? destination.bottom - height
          : destination.top + (destination.height - height) / 2,
      width,
      height,
    );
    _draw(canvas, atlas.image, crop, target, alpha: alpha, flipX: flipX);
    return true;
  }

  bool drawAnchored(
    ui.Canvas canvas,
    String key,
    String animation,
    double x,
    double y,
    double targetHeight, {
    int frameIndex = 0,
    bool flipX = false,
    double alpha = 1,
    double? metricHeight,
  }) {
    final atlas = _atlases[key];
    final frame = atlas?.frame(animation, frameIndex);
    if (atlas == null || frame == null || frame.content.isEmpty) return false;
    final crop = frame.content;
    final scale = targetHeight / (metricHeight ?? crop.height);
    final left = x - (frame.anchorX - crop.left) * scale;
    final top = y - (frame.anchorY - crop.top) * scale;
    final target = ui.Rect.fromLTWH(
      left,
      top,
      crop.width * scale,
      crop.height * scale,
    );
    _draw(
      canvas,
      atlas.image,
      crop,
      target,
      alpha: alpha,
      flipX: flipX,
      pivotX: x,
    );
    return true;
  }

  void drawBackground(ui.Canvas canvas, String key, ui.Rect destination) {
    final atlas = _atlases[key];
    if (atlas == null) return;
    final image = atlas.image;
    final sourceAspect = image.width / image.height;
    final targetAspect = destination.width / destination.height;
    ui.Rect source;
    if (sourceAspect > targetAspect) {
      final sourceWidth = image.height * targetAspect;
      source = ui.Rect.fromLTWH(
        (image.width - sourceWidth) / 2,
        0,
        sourceWidth,
        image.height.toDouble(),
      );
    } else {
      final sourceHeight = image.width / targetAspect;
      source = ui.Rect.fromLTWH(
        0,
        image.height - sourceHeight,
        image.width.toDouble(),
        sourceHeight,
      );
    }
    canvas.drawImageRect(
      image,
      source,
      destination,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  void dispose() {
    for (final atlas in _atlases.values) {
      atlas.image.dispose();
    }
    _atlases.clear();
  }

  void _draw(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect source,
    ui.Rect destination, {
    double alpha = 1,
    bool flipX = false,
    double? pivotX,
  }) {
    canvas.save();
    if (flipX) {
      canvas.translate((pivotX ?? destination.center.dx) * 2, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
      image,
      source,
      destination,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = ui.Color.fromRGBO(
          255,
          255,
          255,
          alpha.clamp(0.0, 1.0).toDouble(),
        ),
    );
    canvas.restore();
  }
}
