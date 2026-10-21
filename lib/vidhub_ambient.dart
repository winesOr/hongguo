import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// VidHub 风格的环境氛围色体系。
///
/// 规格来自对 VidHub Android 3.0.2 的逆向实证：
/// * 取色只采样约 1024 个点（步长下采样），单张耗时压在 2ms 内；
/// * HSV 三重去噪：纯黑（明度 < 0.12）、纯灰（饱和 < 0.12）、
///   高光过曝（饱和 < 0.18 且明度 > 0.85）全部剔除；
/// * 最终 RGB 统一压暗 22%，让色彩沉降为内敛的环境底色；
/// * 极端情况（黑白老片）回退到暗夜冷灰 #16191D；
/// * 128 容量 LRU 缓存，滑回已看过的海报零开销。
class AmbientPalette {
  AmbientPalette._();

  /// VidHub 的默认暗夜冷灰。
  static const Color fallback = Color(0xFF16191D);

  /// 底色压暗系数：Color * 0.78。
  static const double _dim = 0.78;

  /// 单张图片的最大采样点数。
  static const int _sampleBudget = 1024;

  /// 取色用的微缩图边长。
  static const int _thumbEdge = 64;

  static const int _cacheCapacity = 128;

  static final LinkedHashMap<String, Color> _cache = LinkedHashMap();

  /// 正在解码的封面，避免同一张图并发重复解码。
  static final Map<String, Future<Color>> _inflight = {};

  static Color _remember(String key, Color color) {
    _cache.remove(key);
    _cache[key] = color;
    while (_cache.length > _cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return color;
  }

  /// 读取缓存命中值；未命中返回 null。
  static Color? peek(String key) => _cache[key];

  /// 从本地封面文件提取氛围色。失败或图不存在时返回 [fallback]。
  static Future<Color> fromCoverFile(String path) {
    if (path.isEmpty) return Future.value(fallback);
    final cached = _cache[path];
    if (cached != null) {
      _remember(path, cached);
      return Future.value(cached);
    }
    final pending = _inflight[path];
    if (pending != null) return pending;
    final future = _extract(path).then((color) {
      _remember(path, color);
      return color;
    }).whenComplete(() => _inflight.remove(path));
    _inflight[path] = future;
    return future;
  }

  static Future<Color> _extract(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return fallback;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return fallback;
      // 先解成微缩图：VidHub 同样先走 Glide 的微缩解码再取色，
      // 避免遍历 1080P 原图的百万级像素。
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _thumbEdge,
        targetHeight: _thumbEdge,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return fallback;
        return colorFromRgba(data.buffer.asUint8List());
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return fallback;
    }
  }

  /// 步长下采样 + 三重去噪后的加权均值。
  ///
  /// 纯函数，不碰 I/O 与图片解码，便于单测覆盖算法本身。
  static Color colorFromRgba(Uint8List rgba) {
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return fallback;
    final rawStep = pixels ~/ _sampleBudget;
    final step = rawStep < 1 ? 1 : rawStep;

    var r = 0.0, g = 0.0, b = 0.0, weight = 0.0;
    for (var index = 0; index < pixels; index += step) {
      final offset = index * 4;
      final alpha = rgba[offset + 3];
      if (alpha < 8) continue;
      final red = rgba[offset] / 255.0;
      final green = rgba[offset + 1] / 255.0;
      final blue = rgba[offset + 2] / 255.0;

      final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[offset], rgba[offset + 1], rgba[offset + 2]));
      final brightness = hsv.value;
      final saturation = hsv.saturation;

      // 纯黑：暗部会把整体拉向死黑。
      if (brightness < 0.12) continue;
      // 纯灰：灰度像素没有情绪倾向。
      if (saturation < 0.12) continue;
      // 高光过曝：白字幕/白底会让浅色背景刺眼发白。
      if (saturation < 0.18 && brightness > 0.85) continue;

      // 中段明度的像素更能代表海报情绪，给予更高权重。
      final w = 1.0 - (brightness - 0.55).abs().clamp(0.0, 0.55);
      r += red * w;
      g += green * w;
      b += blue * w;
      weight += w;
    }

    if (weight <= 0) return fallback;

    r = (r / weight) * _dim;
    g = (g / weight) * _dim;
    b = (b / weight) * _dim;

    // 压暗后再兜一次底：接近死黑的颜色没有氛围意义。
    final maxChannel = math.max(r, math.max(g, b));
    if (maxChannel < 0.06) return fallback;

    return Color.from(
      alpha: 1,
      red: r.clamp(0.0, 1.0),
      green: g.clamp(0.0, 1.0),
      blue: b.clamp(0.0, 1.0),
    );
  }

  /// 测试与排障用：清空缓存。
  static void clearCache() => _cache.clear();
}

/// 全景贯通流光背景。
///
/// 三层结构（与 VidHub 一致）：
/// 1. 底色填充；
/// 2. 右上角非对称辐射流光 —— 中心 (0.45, -0.65)、半径 1.35、主色 45% 透明度；
/// 3. 22% 磨砂纯黑对比度护盾 + 多阶非线性消退渐变，消除 OLED 硬切边。
///
/// 颜色变化走 380ms 减速插值，模拟 VidHub 的"色彩呼吸"。
class AmbientGlow extends StatelessWidget {
  const AmbientGlow({
    super.key,
    required this.color,
    this.baseColor = const Color(0xFF121416),
    this.child,
    this.animate = true,
  });

  /// 由海报提取出的氛围色。
  final Color color;

  /// 消退渐变最终闭合的底色。
  final Color baseColor;

  final Widget? child;

  /// 关掉可避免在测试或静态场景下产生动画噪音。
  final bool animate;

  static const Duration breath = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    if (!animate) return _paint(color);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: breath,
      curve: Curves.decelerate,
      builder: (context, value, _) => _paint(value ?? color),
    );
  }

  Widget _paint(Color tone) {
    // 流光主色：约 45% 透明度，向四周自然衰减。
    final glow = tone.withValues(alpha: 0.45);
    final halo = tone.withValues(alpha: 0.22);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: baseColor),
        // 右上角斜向微光，给屏幕上方叠出光影厚度。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                halo,
                Colors.transparent,
              ],
              stops: const [0.0, 0.62],
            ),
          ),
        ),
        // 非对称辐射流光：模拟影院顶部射灯打在海报边缘的漫射。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.45, -0.65),
              radius: 1.35,
              colors: [
                glow,
                tone.withValues(alpha: 0.18),
                Colors.transparent,
              ],
              stops: const [0.0, 0.42, 1.0],
            ),
          ),
        ),
        // 对比度护盾：恒定 22% 纯黑，肉眼几乎不可察，
        // 但保证前景白字/徽章在任何海报色下都留在无障碍对比度安全区。
        const ColoredBox(color: Color(0x38000000)),
        // 多阶非线性消退：0→45% 全透明，45→72% 微升，
        // 72→94% 快速过渡到底色，94% 处彻底闭合。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                baseColor.withValues(alpha: 0.35),
                baseColor.withValues(alpha: 0.92),
                baseColor,
              ],
              stops: const [0.0, 0.45, 0.72, 0.94, 1.0],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// 悬浮海报卡片：不占满屏宽，左右微露邻卡边缘，14dp 大圆角 + 柔和投影。
class FloatingPosterCard extends StatelessWidget {
  const FloatingPosterCard({
    super.key,
    required this.child,
    this.radius = 14,
    this.elevated = true,
  });

  final Widget child;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 28,
                  spreadRadius: -6,
                  offset: Offset(0, 14),
                ),
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

/// 跟随当前海报切换氛围色的容器。
///
/// 传入封面文件路径即可；路径为空或解码失败时自动回退到 VidHub 冷灰。
class AmbientCoverScope extends StatefulWidget {
  const AmbientCoverScope({
    super.key,
    required this.coverPath,
    required this.builder,
    this.baseColor = const Color(0xFF121416),
  });

  final String? coverPath;
  final Widget Function(BuildContext context, Color tone) builder;
  final Color baseColor;

  @override
  State<AmbientCoverScope> createState() => _AmbientCoverScopeState();
}

class _AmbientCoverScopeState extends State<AmbientCoverScope> {
  Color _tone = AmbientPalette.fallback;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AmbientCoverScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverPath != widget.coverPath) _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.coverPath;
    if (path == null || path.isEmpty) {
      if (mounted && _tone != AmbientPalette.fallback) {
        setState(() => _tone = AmbientPalette.fallback);
      }
      return;
    }
    final cached = AmbientPalette.peek(path);
    if (cached != null) {
      if (mounted && cached != _tone) setState(() => _tone = cached);
      return;
    }
    final generation = ++_generation;
    final tone = await AmbientPalette.fromCoverFile(path);
    if (!mounted || generation != _generation) return;
    setState(() => _tone = tone);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tone);
}
