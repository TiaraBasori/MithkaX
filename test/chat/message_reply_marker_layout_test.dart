import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 1,
        accountUserId: 1,
        query: (request) async => <String, dynamic>{'@type': 'ok'},
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  Future<ThemeController> pumpBubble(
    WidgetTester tester,
    ChatMessage message, {
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                MessageBubble(
                  message: message,
                  peerTitle: 'Peer',
                  isGroup: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return theme;
  }

  ChatMessage quotedReply() => ChatMessage(
    id: 21,
    isOutgoing: false,
    text: 'reply body',
    date: 1,
    contentType: 'messageText',
    replyToMessageId: 22,
    replyToDate: 1,
    replyToQuote: const MessageTextQuote(
      text:
          'The quoted original message is long enough to need several lines '
          'inside the reply marker at a large text scale as well, so the panel '
          'has to grow with the text instead of clipping its bottom. A fourth '
          'sentence makes sure it wraps and might hit the cap.',
      position: 0,
    ),
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets('a long quote keeps its preview whole at text scale $scale', (
      tester,
    ) async {
      await pumpBubble(tester, quotedReply(), textScale: scale);
      final marker = find.byKey(const ValueKey('messageReplyQuote'));
      expect(marker, findsOneWidget);
      final panel = tester.getRect(marker);
      // The panel grows with its text: a multi-line quote is taller than a
      // one-line preview, and nothing under it squeezes the panel shut.
      expect(panel.height, greaterThan(scale > 1 ? 60 : 40));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 11));
    });
  }

  testWidgets('a sticker reply marker and its time use the page ink', (
    tester,
  ) async {
    final message =
        ChatMessage(
            id: 3,
            isOutgoing: true,
            text: '',
            date: 1,
            contentType: 'messageSticker',
            stickerFileId: 7,
            image: TdFileRef(id: 5),
            imageWidth: 512,
            imageHeight: 512,
            replyToMessageId: 4,
            replyToDate: 1,
          )
          ..replyToSender = 'Someone'
          ..replyToPreview =
              'quoted line that is long enough to wrap elsewhere';
    await pumpBubble(tester, message);

    final band = find.byKey(const ValueKey('messageBandTime-3'));
    expect(band, findsOneWidget, reason: 'the time rides the outside band');
    final time = tester.widget<Text>(
      find.descendant(of: band, matching: find.byType(Text)).first,
    );
    // A bubble-less sticker draws its band on the page. The theme's outgoing
    // bubble ink is white, which vanished on a light wallpaper.
    expect(time.style?.color?.computeLuminance(), lessThan(0.5));

    final preview = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('messageReplyQuote')),
            matching: find.byType(Text),
          ),
        )
        .firstWhere((text) => (text.data ?? '').isNotEmpty);
    expect(preview.style?.color?.computeLuminance(), lessThan(0.5));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 11));
  });
}
