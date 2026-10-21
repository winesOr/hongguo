import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'models.dart';
import 'vidhub_ambient.dart';

/// VidHub 式悬浮海报轮播。
///
/// 与 VidHub 一致地做「空间解耦」：
/// * 海报是悬浮卡片，不占满屏宽，左右微露邻卡边缘形成连续滑动暗示；
/// * 文字信息层与图片层是两个独立组件，靠页码同步联动，
///   文字走自己的淡入淡出，不跟着海报机械位移；
/// * 当前页的封面会提取氛围色，通过 [onTone] 抛给外层做全屏流光。
class VidHubHero extends StatefulWidget {
  const VidHubHero({
    super.key,
    required this.items,
    required this.repository,
    required this.onOpen,
    this.onTone,
    this.maxItems = 12,
    this.cardWidth = 232,
    this.showInfo = true,
  });

  final List<Drama> items;
  final AppRepository repository;
  final ValueChanged<Drama> onOpen;

  /// 当前海报的氛围色变化回调。
  final ValueChanged<Color>? onTone;

  final int maxItems;
  final double cardWidth;
  final bool showInfo;

  @override
  State<VidHubHero> createState() => _VidHubHeroState();
}

class _VidHubHeroState extends State<VidHubHero> {
  late final PageController _controller;
  final Map<String, String> _covers = {};
  int _index = 0;
  int _toneGeneration = 0;

  List<Drama> get _items =>
      widget.items.length > widget.maxItems
      ? widget.items.sublist(0, widget.maxItems)
      : widget.items;

  Drama? get _current {
    final items = _items;
    if (items.isEmpty) return null;
    return items[_index.clamp(0, items.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.86);
    unawaited(_resolveCovers());
  }

  @override
  void didUpdateWidget(covariant VidHubHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.items.length != widget.items.length ||
        (widget.items.isNotEmpty &&
            oldWidget.items.isNotEmpty &&
            oldWidget.items.first.id != widget.items.first.id);
    if (changed) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      unawaited(_resolveCovers());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolveCovers() async {
    final items = _items;
    // 先按当前页定氛围色，再补齐其余封面，避免首屏等所有图。
    if (items.isNotEmpty) await _syncTone(items[0]);
    for (final drama in items) {
      if (!mounted) return;
      if (_covers.containsKey(drama.id)) continue;
      try {
        final path = await widget.repository.cover(drama);
        if (!mounted) return;
        setState(() => _covers[drama.id] = path);
      } catch (_) {
        // 单张封面失败不影响其余卡片，占位图会兜住。
      }
    }
  }

  Future<void> _syncTone(Drama? drama) async {
    if (drama == null) return;
    final path = _covers[drama.id];
    if (path == null || path.isEmpty) return;
    final generation = ++_toneGeneration;
    final tone = await AmbientPalette.fromCoverFile(path);
    if (!mounted || generation != _toneGeneration) return;
    widget.onTone?.call(tone);
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    final items = _items;
    if (items.isEmpty) return;
    unawaited(_syncTone(items[index.clamp(0, items.length - 1)]));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.min(
          widget.cardWidth,
          constraints.maxWidth * 0.86,
        );
        // 竖版海报约 3:4.2，与红果官方封面比例接近。
        final posterHeight = cardWidth * 1.42;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: posterHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: items.length,
                onPageChanged: _onPageChanged,
                padEnds: true,
                itemBuilder: (context, index) {
                  final drama = items[index];
                  final cover = _covers[drama.id];
                  final active = index == _index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => widget.onOpen(drama),
                      child: AnimatedScale(
                        scale: active ? 1.0 : 0.94,
                        duration: AmbientGlow.breath,
                        curve: Curves.decelerate,
                        child: AnimatedOpacity(
                          opacity: active ? 1.0 : 0.72,
                          duration: AmbientGlow.breath,
                          child: FloatingPosterCard(
                            radius: 14,
                            child: cover == null || cover.isEmpty
                                ? _HeroCoverPlaceholder(drama: drama)
                                : Image.file(
                                    File(cover),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stack) =>
                                        _HeroCoverPlaceholder(drama: drama),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.showInfo) _info(context),
          ],
        );
      },
    );
  }

  /// 独立信息层：与海报解耦，自己走淡入淡出。
  Widget _info(BuildContext context) {
    final drama = _current;
    if (drama == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final meta = <String>[
      if (drama.episodes > 0) '${drama.episodes} 集',
      if (drama.category.isNotEmpty) drama.category,
      if (drama.releaseStatus.isNotEmpty) drama.releaseLabel,
      ...drama.tags.take(2),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: AnimatedSwitcher(
        duration: AmbientGlow.breath,
        switchInCurve: Curves.decelerate,
        switchOutCurve: Curves.decelerate,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(drama.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: 0.2,
                color: Colors.white,
                shadows: const [
                  Shadow(color: Color(0x99000000), blurRadius: 12),
                ],
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final text in meta)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          text,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => widget.onOpen(drama),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF121416),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('立即播放'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCoverPlaceholder extends StatelessWidget {
  const _HeroCoverPlaceholder({required this.drama});

  final Drama drama;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1E2125),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            drama.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA7ADB4),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
