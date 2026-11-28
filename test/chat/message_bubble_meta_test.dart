//
//  message_bubble_meta_test.dart
//
//  The send time reads OUTSIDE the surface, the pre-1.14 way: a floating label
//  58dp in from the row's trailing edge and 5dp past its bottom, armed by the
//  theme setting, a tap or hover; a leading slot on the chip band when the
//  bubble has one; beside the sender name in a group. This suite pins all
//  three, plus the clock-only label.
//

import 'dart:async';

import 'package:flutter/gestures.dart';
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
    bool forceShowTimestamp = true,
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
                forceShowTimestamp: forceShowTimestamp,
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

  testWidgets('an armed time floats under the bubble, 58dp in', (tester) async {
    // No band chips on this message, so the floating label carries the time.
    await pumpBubble(tester, message());
    final time = find.byKey(const ValueKey('messageTappedTimestamp'));
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-9')),
    );
    final row = tester.getRect(find.byType(MessageBubble));
    expect(time, findsOneWidget);
    final timeRect = tester.getRect(time);
    // Its pre-1.14 place: 58dp in from the row's trailing side, hanging 5dp
    // past the row's bottom edge.
    expect((row.right - timeRect.right - 58).abs(), lessThan(1.5));
    expect((timeRect.bottom - row.bottom - 5).abs(), lessThan(1.5));
    expect(timeRect.top, greaterThan(bubble.bottom - 6));
    // Clock only, never a date.
    final label = tester.widget<Text>(time).data ?? '';
    expect(
      RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(label),
      isTrue,
      reason: 'the label reads $label',
    );
  });

  testWidgets('an outgoing bubble with a band leads it with the time', (
    tester,
  ) async {
    await pumpBubble(tester, message(viewCount: 42));
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-9')),
    );
    final views = tester.getRect(find.byKey(const ValueKey('messageViews-9')));
    final time = find.byKey(const ValueKey('messageTappedTimestamp'));
    expect(time, findsOneWidget);
    final timeRect = tester.getRect(time);
    // The band row hangs under the bubble; the time leads it, left of the chip.
    expect(timeRect.top, greaterThanOrEqualTo(bubble.bottom - 1));
    expect(timeRect.right, lessThanOrEqualTo(views.left));
    expect((views.center.dy - timeRect.center.dy).abs(), lessThan(6));
  });

  testWidgets('without the setting and without hover no time shows', (
    tester,
  ) async {
    await pumpBubble(tester, message(), forceShowTimestamp: false);
    expect(find.byKey(const ValueKey('messageTappedTimestamp')), findsNothing);
    // Hover brings it in.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('messageTextBubble-9'))),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('messageTappedTimestamp')),
      findsOneWidget,
    );
  });

  testWidgets('a group album carries the time after the sender name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'alwaysShowMessageTime': true});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    ChatMessage tile(int id, String text) => ChatMessage(
      id: id,
      isOutgoing: false,
      text: text,
      date: 1700000000,
      contentType: 'messageDocument',
      senderId: 2,
      senderName: 'Alice',
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
                messages: [tile(31, 'Caption'), tile(32, '')],
                peerTitle: 'Channel',
                isGroup: true,
                meId: 1,
                onOpenImage: (message) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final header = tester.getRect(
      find.byKey(const ValueKey('messageSenderHeader-31')),
    );
    final time = tester.getRect(
      find.byKey(const ValueKey('messageTappedTimestamp')).first,
    );
    final card = tester.getRect(
      find.byKey(const ValueKey('messageImageAlbumCard-31')),
    );
    // The pre-1.14 slot sits on the name's line, above the card.
    expect(header.contains(time.center), isTrue);
    expect(time.top, lessThan(card.top));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('an album without a sender row carries no time', (tester) async {
    SharedPreferences.setMockInitialValues({'alwaysShowMessageTime': true});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    ChatMessage tile(int id) => ChatMessage(
      id: id,
      isOutgoing: false,
      text: '',
      date: 1700000000,
      contentType: 'messageDocument',
      senderId: 2,
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
                peerTitle: 'Peer',
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
    expect(find.byKey(const ValueKey('messageTappedTimestamp')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
