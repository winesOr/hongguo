import 'dart:typed_data';

import 'package:duanju_app/vidhub_ambient.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造纯色 RGBA 缓冲，模拟一张 64×64 的海报微缩图。
Uint8List solidRgba(int r, int g, int b, {int pixels = 64 * 64}) {
  final data = Uint8List(pixels * 4);
  for (var index = 0; index < pixels; index++) {
    final offset = index * 4;
    data[offset] = r;
    data[offset + 1] = g;
    data[offset + 2] = b;
    data[offset + 3] = 255;
  }
  return data;
}

void main() {
  group('AmbientPalette.colorFromRgba 取色与去噪', () {
    test('纯黑海报回退到 VidHub 暗夜冷灰', () {
      final tone = AmbientPalette.colorFromRgba(solidRgba(0, 0, 0));
      expect(tone, AmbientPalette.fallback);
    });

    test('纯灰海报被饱和度阈值剔除并回退', () {
      final tone = AmbientPalette.colorFromRgba(solidRgba(128, 128, 128));
      expect(tone, AmbientPalette.fallback);
    });

    test('高光过曝的白色被剔除并回退', () {
      final tone = AmbientPalette.colorFromRgba(solidRgba(250, 250, 250));
      expect(tone, AmbientPalette.fallback);
    });

    test('高饱和红海报取到偏红色调且按 0.78 压暗', () {
      // #E53935
      final tone = AmbientPalette.colorFromRgba(solidRgba(229, 57, 53));
      expect(tone, isNot(AmbientPalette.fallback));
      expect(tone.r, greaterThan(tone.g));
      expect(tone.r, greaterThan(tone.b));
      // 原始红分量约 0.898，压暗后必须明显低于它。
      expect(tone.r, lessThan(0.85));
      expect(tone.r, greaterThan(0.60));
    });

    test('深蓝海报取到偏蓝色调', () {
      // #1E88E5
      final tone = AmbientPalette.colorFromRgba(solidRgba(30, 136, 229));
      expect(tone, isNot(AmbientPalette.fallback));
      expect(tone.b, greaterThan(tone.r));
      expect(tone.b, greaterThan(tone.g));
    });

    test('空缓冲安全回退，不抛异常', () {
      final tone = AmbientPalette.colorFromRgba(Uint8List(0));
      expect(tone, AmbientPalette.fallback);
    });

    test('全透明像素被跳过并回退', () {
      final data = Uint8List(64 * 64 * 4); // alpha 全 0
      expect(AmbientPalette.colorFromRgba(data), AmbientPalette.fallback);
    });
  });

  testWidgets('AmbientGlow 渲染出流光层与对比度护盾', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientGlow(
            color: Color(0xFF8B1A1A),
            animate: false,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AmbientGlow), findsOneWidget);
    // 斜向微光 + 辐射流光 + 消退渐变，至少三层 DecoratedBox。
    expect(find.byType(DecoratedBox), findsAtLeastNWidgets(3));
  });

  testWidgets('AmbientGlow 在动画模式下也能稳定渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientGlow(
            color: Color(0xFF1E88E5),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AmbientGlow), findsOneWidget);
  });
}
