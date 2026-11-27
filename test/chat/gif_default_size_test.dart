//
//  gif_default_size_test.dart
//
//  A chat GIF renders at 60% of the photo media budget at the default 100%
//  preference: the old 320pt-wide box read as an oversized block, and the
//  reference client's animations sit around 200pt. The sticker/GIF slider
//  still scales from that baseline.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Directory _scratch;
late File _still;

Future<Size> _gifBox(WidgetTester tester, {double stickerSize = 14}) async {
  tester.view
    ..physicalSize = const Size(1260, 2700)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  if (stickerSize != 14) theme.stickerMediaSize = stickerSize;
  final message = ChatMessage(
    id: 77,
    isOutgoing: false,
    text: '',
    date: 10,
    contentType: 'messageAnimation',
    imageWidth: 320,
    imageHeight: 180,
    image: TdFileRef(id: 1, localPath: _still.path),
    video: TdFileRef(id: 2, localPath: '${_scratch.path}/missing.mp4'),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            peerTitle: 'TrollStore',
            isGroup: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return tester.getSize(find.byKey(const ValueKey('message-animation-77')));
}

void main() {
  // Real file I/O cannot run inside the widget tests' fake async zone.
  setUpAll(() {
    _scratch = Directory.systemTemp.createTempSync('gif-size');
    _still = File('${_scratch.path}/still.jpg')..writeAsBytesSync([0, 1, 2]);
  });
  tearDownAll(() {
    if (_scratch.existsSync()) _scratch.deleteSync(recursive: true);
  });

  testWidgets('a GIF takes 60% of the photo lane at 100%', (tester) async {
    final box = await _gifBox(tester);
    // 420pt viewport → bubble lane 315; GIF lane 60% = 189. The 320×180
    // source fits the lane exactly, so the box is 189 wide and 106.3 tall.
    expect(box.width, closeTo(189, 0.5));
    expect(box.height, closeTo(189 * 180 / 320, 0.5));
  });

  testWidgets('the sticker/GIF preference still scales the baseline', (
    tester,
  ) async {
    // 20% shrinks the baseline; the lane caps growth at 100%+ (a wide GIF
    // never overflows the bubble).
    final small = await _gifBox(tester, stickerSize: 2);
    expect(small.width, closeTo(189 * 0.2, 0.5));
    final large = await _gifBox(tester, stickerSize: 20);
    expect(large.width, closeTo(189, 0.5));
  });
}
