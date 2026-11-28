import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/media_spoiler.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
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

Future<ui.Image> _decode(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

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

  testWidgets('a captioned photo crops into its widened frame instead of '
      'stretching the picture', (tester) async {
    SharedPreferences.setMockInitialValues({'groupImageMessages': true});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // A real 3:4 bitmap, larger than the cache box the 300pt-wide frame asks
    // for at this density, so the decode is a real resize.
    final bytes = await tester.runAsync(() async {
      final source = await createTestImage(width: 1200, height: 1600);
      final data = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      return data!.buffer.asUint8List();
    });

    final message = ChatMessage(
      id: 7001,
      isOutgoing: false,
      text: '这是一段很长的图片说明文字，长度超过图片本身的宽度，会把气泡拉到整行',
      date: 1,
      contentType: 'messagePhoto',
      image: TdFileRef(id: 7002, miniThumb: bytes),
      imageWidth: 300,
      imageHeight: 400,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubble(
                message: message,
                peerTitle: 'peer',
                isGroup: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final photo = find.byWidgetPredicate(
      (widget) => widget is TDImage && widget.photo?.id == 7002,
    );
    expect(photo, findsOneWidget);
    // The caption widened the frame past the photo's own 3:4 shape, so the
    // frame is a crop target rather than the source ratio.
    final frame = tester.getRect(find.byType(MessageMediaSpoiler));
    expect(frame.width / frame.height, greaterThan(0.9));

    final image = tester.widget<Image>(
      find.descendant(of: photo, matching: find.byType(Image)),
    );
    final decoded = await tester.runAsync(() => _decode(image.image));
    expect(decoded, isNotNull);
    // The bitmap keeps the source's proportions; `BoxFit.cover` crops it into
    // the wider frame. A both-sides decode returns 1:1 here — the stretched
    // picture the report described.
    expect(decoded!.width / decoded.height, closeTo(0.75, 0.02));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 11));
  });
}
