//
//  media_reply_marker_test.dart
//
//  A photo, video or GIF with no caption that answers another message draws
//  the reply marker ABOVE the media, the way a sticker does. Wrapping the
//  picture and the marker in a filled bubble read as a quote card glued to
//  media that has no caption to group with. A caption or an attribution
//  header still needs that bubble, and a sticker keeps its own treatment.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/chat/messages/stretchable_message_bubble_background.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Directory scratch;
  late String photoPath;

  setUpAll(() {
    // A real local file keeps TDImage's resolver synchronous: a bare file id
    // parks a download waiter that flutter_test reports as a pending timer.
    scratch = Directory.systemTemp.createTempSync('media_reply_marker');
    photoPath = '${scratch.path}/photo.png';
    File(photoPath).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      ),
    );
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

  tearDownAll(() {
    updates.close();
    scratch.deleteSync(recursive: true);
  });

  Future<void> pumpBubble(
    WidgetTester tester,
    ChatMessage message, {
    bool groupCaptions = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'groupImageMessages': groupCaptions,
    });
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1260, 2736)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MessageBubble(
                  message: message,
                  peerTitle: 'Ada',
                  isGroup: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  ChatMessage photo({required String text}) =>
      ChatMessage(
          id: 61,
          isOutgoing: false,
          text: text,
          date: 10,
          contentType: 'messagePhoto',
          image: TdFileRef(id: 61, localPath: photoPath),
          imageWidth: 800,
          imageHeight: 600,
          replyToMessageId: 12,
          replyToDate: 9,
        )
        ..replyToSender = 'Ada'
        ..replyToPreview = 'the message being answered';

  testWidgets('a caption-less photo reply floats its marker above the photo', (
    tester,
  ) async {
    await pumpBubble(tester, photo(text: ''));

    final quote = find.byKey(const ValueKey('messageReplyQuote'));
    expect(quote, findsOneWidget);
    // The bare marker replaces the filled media bubble: no messageRepliedMedia
    // card, and no bubble surface between the marker and the page.
    expect(find.byKey(const ValueKey('messageRepliedMedia-61')), findsNothing);
    expect(
      find.ancestor(
        of: quote,
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
      findsNothing,
      reason: 'no bubble decoration is painted behind the reply marker',
    );

    // The quoted line is really rendered inside the marker.
    expect(
      find.descendant(
        of: quote,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('the message being answered'),
        ),
      ),
      findsOneWidget,
    );

    // The marker hangs above the picture, not beside it or inside a card.
    final media = find.byKey(const ValueKey('messageMediaClip-61'));
    expect(media, findsOneWidget);
    final quoteRect = tester.getRect(quote);
    final mediaRect = tester.getRect(media);
    expect(quoteRect.bottom, lessThanOrEqualTo(mediaRect.top));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a captioned photo reply keeps the filled bubble', (
    tester,
  ) async {
    // Captions grouped onto the picture take the other branch; disabling the
    // grouping exercises the same branch this fix touches, where a caption
    // still needs the bubble that holds the marker.
    await pumpBubble(tester, photo(text: 'a caption'), groupCaptions: false);

    final bubble = find.byKey(const ValueKey('messageRepliedMedia-61'));
    expect(bubble, findsOneWidget);
    final quote = find.byKey(const ValueKey('messageReplyQuote'));
    expect(quote, findsOneWidget);
    expect(find.descendant(of: bubble, matching: quote), findsOneWidget);
    expect(
      find.ancestor(
        of: quote,
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('a caption'),
      ),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a sticker reply keeps its marker above the sticker', (
    tester,
  ) async {
    final sticker =
        ChatMessage(
            id: 71,
            isOutgoing: false,
            text: '',
            date: 10,
            contentType: 'messageSticker',
            stickerFileId: 500,
            image: TdFileRef(id: 500, localPath: photoPath),
            replyToMessageId: 12,
            replyToDate: 9,
          )
          ..replyToSender = 'Ada'
          ..replyToPreview = 'the message being answered';
    await pumpBubble(tester, sticker);

    final quote = find.byKey(const ValueKey('messageReplyQuote'));
    expect(quote, findsOneWidget);
    expect(
      find.ancestor(
        of: quote,
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
      findsNothing,
    );
    final stickerImage = find.byType(TDImage).first;
    expect(
      tester.getRect(quote).bottom,
      lessThanOrEqualTo(tester.getRect(stickerImage).top),
    );

    expect(tester.takeException(), isNull);
  });
}
