//
//  message_bubble_meta_test.dart
//
//  Every message carries its send time OUTSIDE, on the band under the bubble,
//  leading the view/forward/reply chips and right-aligned to the bubble's own
//  edge. A corner stamp costs a strip of every bubble and lands ON the artwork
//  of a photo, sticker or album, so this suite pins the outside geometry.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/image_media_album_bubble.dart';
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
        query: (request) async => switch (request['@type']) {
          'getCustomEmojiStickers' => <String, dynamic>{
            '@type': 'stickers',
            'stickers': const <Map<String, dynamic>>[],
          },
          _ => throw StateError('Unexpected TDLib request: $request'),
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  Future<void> pumpBubble(
    WidgetTester tester,
    ChatMessage message, {
    bool outgoing = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubble(
                message: message,
                peerTitle: 'Channel',
                isGroup: false,
                meId: 1,
                forceShowTimestamp: true,
                showChannelPostStats: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  ChatMessage message({
    int id = 9,
    bool outgoing = true,
    int viewCount = 0,
    String text = 'A post',
  }) => ChatMessage(
    id: id,
    isOutgoing: outgoing,
    text: text,
    date: 1700000000,
    contentType: 'messageText',
    senderId: outgoing ? 1 : 2,
    senderName: outgoing ? null : 'Alice',
    viewCount: viewCount,
  );

  testWidgets('the send time rides the band under the bubble', (tester) async {
    await pumpBubble(tester, message(viewCount: 42));
    final time = find.byKey(const ValueKey('messageBandTime-9'));
    final bubble = find.byKey(const ValueKey('messageTextBubble-9'));
    expect(time, findsOneWidget);
    expect(bubble, findsOneWidget);

    final timeRect = tester.getRect(time);
    final bubbleRect = tester.getRect(bubble);
    expect(
      timeRect.top,
      greaterThanOrEqualTo(bubbleRect.bottom - 1),
      reason: 'time $timeRect must sit below the bubble $bubbleRect',
    );
    // The time leads the chip cluster; the cluster is what hugs the bubble's
    // own right edge.
    expect((bubbleRect.right - timeRect.right).abs(), greaterThan(0));
    // The views chip shares the row, to the right of the time.
    final views = tester.getRect(find.byKey(const ValueKey('messageViews-9')));
    expect((views.center.dy - timeRect.center.dy).abs(), lessThan(6));
    expect(views.left, greaterThan(timeRect.right));
  });

  testWidgets('a bubble without outside chips still shows its time', (
    tester,
  ) async {
    await pumpBubble(tester, message());
    expect(find.byKey(const ValueKey('messageViews-9')), findsNothing);
    final time = find.byKey(const ValueKey('messageBandTime-9'));
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-9')),
    );
    expect(time, findsOneWidget);
    expect(tester.getRect(time).top, greaterThanOrEqualTo(bubble.bottom - 1));
  });

  testWidgets('an incoming message puts its time in the same place', (
    tester,
  ) async {
    await pumpBubble(tester, message(outgoing: false), outgoing: false);
    final time = tester.getRect(
      find.byKey(const ValueKey('messageBandTime-9')),
    );
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-9')),
    );
    expect(time.top, greaterThanOrEqualTo(bubble.bottom - 1));
    expect((bubble.left - time.left).abs(), lessThan(4));
  });

  testWidgets('an album keeps its time under the card, caption or not', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final albumCaption = ChatMessage(
      id: 31,
      isOutgoing: true,
      text: 'Caption',
      date: 1700000000,
      contentType: 'messageDocument',
      senderId: 1,
      document: MessageDocument(
        fileName: 'a.pdf',
        size: 10,
        ext: 'pdf',
        file: TdFileRef(id: 1),
      ),
    );
    final albumSecond = ChatMessage(
      id: 32,
      isOutgoing: true,
      text: '',
      date: 1700000000,
      contentType: 'messageDocument',
      senderId: 1,
      document: MessageDocument(
        fileName: 'b.pdf',
        size: 10,
        ext: 'pdf',
        file: TdFileRef(id: 2),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ImageMediaAlbumBubble(
                messages: [albumCaption, albumSecond],
                peerTitle: 'Channel',
                isGroup: false,
                meId: 1,
                onOpenImage: (message) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final timeRect = tester.getRect(
      find.byKey(const ValueKey('messageTappedTimestamp')),
    );
    final card = tester.getRect(
      find.byKey(const ValueKey('messageImageAlbumCard-31')),
    );
    expect(
      timeRect.top,
      greaterThanOrEqualTo(card.bottom - 1),
      reason: 'album time $timeRect must sit under the card $card',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a caption-less album keeps the time under the photos', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    ChatMessage tile(int id) => ChatMessage(
      id: id,
      isOutgoing: true,
      text: '',
      date: 1700000000,
      contentType: 'messageDocument',
      senderId: 1,
      document: MessageDocument(
        fileName: '$id.pdf',
        size: 10,
        ext: 'pdf',
        file: TdFileRef(id: id),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ImageMediaAlbumBubble(
                messages: [tile(41), tile(42)],
                peerTitle: 'Channel',
                isGroup: false,
                meId: 1,
                onOpenImage: (message) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final timeRect = tester.getRect(
      find.byKey(const ValueKey('messageTappedTimestamp')),
    );
    final tileRect = tester.getRect(
      find.byKey(const ValueKey('messageImageAlbumTile-41')),
    );
    expect(
      timeRect.top,
      greaterThanOrEqualTo(tileRect.bottom),
      reason: 'the time must sit outside the pictures, below them',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
