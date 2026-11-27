//
//  brand_mark_test.dart
//
//  The in-app mark is ALWAYS the night launcher icon's glyph body — the
//  bright-azure to deep-azure ramp — in light and dark appearance alike. It
//  does not follow the theme colour: derived pale tints turned the logo into a
//  light-blue blob, which the user rejected. The frost ramp is reserved for
//  the splash, which paints the mark on the brand gradient.
//

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/brand_mark.dart';
import 'package:mithka/theme/app_theme.dart';

const _brandKey = ValueKey('brand-mark-capture');

/// Pumps [mark] on white and returns its opaque pixels as RGB triples.
Future<List<List<int>>> _paint(WidgetTester tester, Widget mark) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: RepaintBoundary(
          key: _brandKey,
          child: Center(child: mark),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_brandKey),
  );
  late final List<List<int>> pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    final bytes = data!.buffer.asUint8List();
    final out = <List<int>>[];
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i + 3] < 250) continue;
      final rgb = [bytes[i], bytes[i + 1], bytes[i + 2]];
      // Skip the white page itself.
      if (rgb[0] > 250 && rgb[1] > 250 && rgb[2] > 250) continue;
      out.add(rgb);
    }
    image.dispose();
    pixels = out;
  });
  return pixels;
}

List<double> _mean(List<List<int>> pixels) {
  final totals = [0.0, 0.0, 0.0];
  for (final pixel in pixels) {
    for (var i = 0; i < 3; i++) {
      totals[i] += pixel[i];
    }
  }
  return [for (final total in totals) total / pixels.length];
}

void main() {
  tearDown(() => AppTheme.applyBrand(const Color(AppTheme.defaultBrand)));

  test('the fill is the icon body, identical in both appearances', () {
    final body = brandMarkColors();
    expect(body.length, greaterThanOrEqualTo(3));
    // Bright azure at the top-left, deep azure at the bottom-right.
    expect(
      body.first.computeLuminance(),
      greaterThan(body.last.computeLuminance()),
    );
    for (final stop in body) {
      final hsl = HSLColor.fromColor(stop);
      expect(hsl.saturation, greaterThan(0.6), reason: '$stop');
      expect(hsl.hue, closeTo(210, 8), reason: 'the icon is azure: $stop');
    }
  });

  test('a custom theme colour never repaints the mark', () {
    final before = List<Color>.from(brandMarkColors());
    AppTheme.applyBrand(const Color(0xFFE0443E));
    expect(brandMarkColors(), before);
    AppTheme.applyBrand(const Color(0xFF1F9E4B));
    expect(brandMarkColors(), before);
  });

  test('the frost ramp is the day icon and stays pale', () {
    expect(markFrostColors.first.computeLuminance(), greaterThan(0.9));
    expect(markFrostColors.last.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('a red theme still paints the azure mark', (tester) async {
    AppTheme.applyBrand(const Color(0xFFE0443E));

    final pixels = await _paint(tester, BrandMark(size: 120));
    expect(pixels, isNotEmpty);
    final mean = _mean(pixels);
    expect(mean[2], greaterThan(mean[0] + 60), reason: 'mean $mean');
    expect(mean[2], greaterThan(mean[1] + 20), reason: 'mean $mean');
  });

  testWidgets('the fill is a gradient, not one flat colour', (tester) async {
    final pixels = await _paint(tester, BrandMark(size: 120));
    final blues = pixels.map((pixel) => pixel[2]).toSet();
    expect(
      blues.length,
      greaterThan(8),
      reason: 'a flat fill would give one value',
    );
  });

  testWidgets('the square slot keeps the ink at 72% of its box', (
    tester,
  ) async {
    await tester.pumpWidget(Center(child: BrandMark(size: 100)));
    expect(tester.getSize(find.byType(BrandMark)), const Size(100, 100));

    final ink = tester.getSize(
      find.descendant(
        of: find.byType(BrandMark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(ink.height, closeTo(72, 0.01));
    expect(ink.width / ink.height, closeTo(23 / 24, 0.001));
  });

  testWidgets('the ink constructor hugs the glyph', (tester) async {
    await tester.pumpWidget(Center(child: BrandMark.ink(ink: 84)));
    final box = tester.getSize(find.byType(BrandMark));
    expect(box.height, 84);
    expect(box.width, closeTo(84 * 23 / 24, 0.01));
  });
}
