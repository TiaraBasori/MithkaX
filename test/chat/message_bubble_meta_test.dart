//
//  message_band_timestamp_test.dart
//
//  An own message that carries outside chips reads its send time as the
//  leading item of that same band: one line, the time to the left of every
//  chip. A bubble with no band keeps the floating timestamp exactly where it
//  was, so nothing grows vertically for chats that do not show chips.
//

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

  Future<void> pumpBubble(WidgetTester tester, ChatMessage message) async {
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

  ChatMessage ownMessage({int viewCount = 0}) => ChatMessage(
    id: 9,
    isOutgoing: true,
    text: 'A post',
    date: 1700000000,
    contentType: 'messageText',
    senderId: 1,
    viewCount: viewCount,
  );

  testWidgets('the send time leads the band of an own message', (tester) async {
    await pumpBubble(tester, ownMessage(viewCount: 42));
    final time = find.byKey(const ValueKey('messageTappedTimestamp'));
    final chip = find.byKey(const ValueKey('messageViews-9'));
    expect(time, findsOneWidget);
    expect(chip, findsOneWidget);

    final timeRect = tester.getRect(time);
    final chipRect = tester.getRect(chip);
    expect(
      timeRect.right,
      lessThanOrEqualTo(chipRect.left),
      reason: 'the time sits left of every chip, not above or below it',
    );
    expect(
      (timeRect.center.dy - chipRect.center.dy).abs(),
      lessThan(1.5),
      reason:
          'time ${timeRect.center} and chip ${chipRect.center} share a line',
    );
  });

  testWidgets('a bubble without chips keeps the floating timestamp', (
    tester,
  ) async {
    await pumpBubble(tester, ownMessage());
    expect(find.byKey(const ValueKey('messageViews-9')), findsNothing);
    final time = find.byKey(const ValueKey('messageTappedTimestamp'));
    expect(time, findsOneWidget);
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-9')),
    );
    expect(
      tester.getRect(time).top,
      greaterThanOrEqualTo(bubble.bottom - 1),
      reason: 'no band means no reserved strip: the time stays below the row',
    );
  });
}
