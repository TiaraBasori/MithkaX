import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1x1 PNG, enough for the widget to build an `Image` without touching the
/// network or the TDLib file centre.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a thumbnail decodes by one side, so it keeps its proportions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 100,
                child: TDImage(
                  photo: TdFileRef(id: 1, miniThumb: _onePixelPng),
                  cacheWidth: 900,
                  cacheHeight: 300,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    // Handing the codec BOTH sides makes it resize the bitmap to exactly that
    // box, stretching a picture whose aspect differs — the album tile and the
    // preview frame then show a distorted image with nothing for `cover` to
    // crop. One side keeps the source aspect.
    final provider = image.image as ResizeImage;
    expect(provider.height, isNull);
    expect(provider.width, 900);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    // Outlast the file loader's download-stall timer.
    await tester.pump(const Duration(minutes: 11));
  });
}
