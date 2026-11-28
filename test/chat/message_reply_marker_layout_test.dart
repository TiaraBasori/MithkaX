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
    bool themingEnabled = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    theme.themingEnabled = themingEnabled;
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
                  forceShowTimestamp: true,
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

  for (final themingEnabled in [true, false]) {
    testWidgets('a sticker reply marker and its time use the page ink '
        '(theming ${themingEnabled ? 'on' : 'off'})', (tester) async {
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
      await pumpBubble(tester, message, themingEnabled: themingEnabled);

      final timeFinder = find.byKey(const ValueKey('messageTappedTimestamp'));
      expect(timeFinder, findsOneWidget, reason: 'the time floats outside');
      final time = tester.widget<Text>(timeFinder);
      // A bubble-less sticker draws its label on the page. The theme's
      // outgoing bubble ink is white, which vanished on a light wallpaper —
      // and with theming switched off that bubble ink is the only ink there
      // would otherwise be.
      expect(time.style?.color?.computeLuminance(), lessThan(0.5));

      // The time sits UNDER the sticker, never on it.
      final sticker = tester.getRect(
        find.byKey(const ValueKey('messageStaticStickerPaint-3')),
      );
      expect(
        tester.getRect(timeFinder).top,
        greaterThan(sticker.bottom - 6),
        reason: 'the label hangs below the sticker, not over it',
      );

      final preview = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('messageReplyQuote')),
              matching: find.byType(Text),
            ),
          )
          .firstWhere((text) => (text.data ?? '').isNotEmpty);
      expect(preview.style?.color?.computeLuminance(), lessThan(0.5));

      // The 3dp rule and the 10% wash take the same page ink.
      final panel = tester.widget<Container>(
        find.byKey(const ValueKey('messageReplyQuote')),
      );
      final decoration = panel.decoration! as BoxDecoration;
      final rule = (decoration.border! as Border).left.color;
      expect(rule.computeLuminance(), lessThan(0.5));
      expect(decoration.color!.computeLuminance(), lessThan(0.5));

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 11));
    });
  }
}
