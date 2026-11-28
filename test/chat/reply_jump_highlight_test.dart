//
//  reply_jump_highlight_test.dart
//
//  Tapping a reply marker jumps to the quoted message. exteraless marks that
//  destination on every platform: the row takes a brand wash immediately,
//  holds it for 1000 ms, then fades it out over 300 ms. The wash used to be
//  desktop-only, so a phone landed on the quoted message with no mark at all.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

var _chatId = 950;
const _peerUserId = 951;

// TDLib server ids live at `server_id << 20`; reply anchors must address ids
// the transcript actually carries.
const _firstSerial = 200;
int _messageId(int serial) => serial << 20;

const _targetText = 'the original body the reply points at';
const _replyAboveText = 'reply sitting beside the target';
const _replyAtBottomText = 'reply sitting at the bottom';
const _messageCount = 30;
const _bottomSerial = _firstSerial + _messageCount - 1;

final _targetId = _messageId(_firstSerial);
final _bottomId = _messageId(_bottomSerial);
final _aboveId = _messageId(_firstSerial + 1);

Map<String, dynamic> _message(int serial, String text, {int? replyToSerial}) {
  return {
    '@type': 'message',
    'id': _messageId(serial),
    'chat_id': _chatId,
    'date': 1700000000 + serial,
    'is_outgoing': false,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': _peerUserId},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': text},
    },
    if (replyToSerial != null)
      'reply_to': {
        '@type': 'messageReplyToMessage',
        'chat_id': _chatId,
        'message_id': _messageId(replyToSerial),
      },
  };
}

/// Oldest→newest. The newest message replies to the second-oldest one, so the
/// jump has to travel most of the transcript; a second reply sits right under
/// the target to re-trigger the jump without scrolling away.
List<Map<String, dynamic>> _history() => [
  _message(_firstSerial, _targetText),
  _message(_firstSerial + 1, _replyAboveText, replyToSerial: _firstSerial),
  for (var serial = _firstSerial + 2; serial < _bottomSerial; serial++)
    _message(serial, 'filler $serial'),
  _message(_bottomSerial, _replyAtBottomText, replyToSerial: _firstSerial),
];

Map<String, dynamic> _messagesResponse(Map<String, dynamic> request) {
  final requested = (request['message_ids'] as List?) ?? const [];
  return {
    '@type': 'messages',
    'messages': [
      for (final id in requested.whereType<int>())
        if (id == _targetId) _message(_firstSerial, _targetText),
    ],
  };
}

Finder _bubbleOf(int messageId) => find.byWidgetPredicate(
  (widget) => widget is MessageBubble && widget.message.id == messageId,
);

Finder _replyMarkerOf(int messageId) => find.descendant(
  of: _bubbleOf(messageId),
  matching: find.byKey(const ValueKey('messageReplyOpenOriginal')),
);

Finder _highlightOf(int messageId) =>
    find.byKey(ValueKey('messageNavigationHighlight-$messageId'));

/// The wash the row is heading for (the AnimatedContainer's own target).
Color? _targetWash(WidgetTester tester, int messageId) {
  final finder = _highlightOf(messageId);
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<AnimatedContainer>(finder);
  final decoration = container.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

/// The wash painted this frame: AnimatedContainer hands its interpolated
/// decoration to a DecoratedBox, which is the first one below the key.
Color? _paintedWash(WidgetTester tester, int messageId) {
  final finder = find.descendant(
    of: _highlightOf(messageId),
    matching: find.byType(DecoratedBox),
  );
  if (finder.evaluate().isEmpty) return null;
  final decoration = tester.widget<DecoratedBox>(finder.first).decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

bool _onScreen(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final view = tester.view;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  return tester.getRect(finder).overlaps(screen);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': _chatId,
            'title': 'Reply chat',
            'type': {'@type': 'chatTypePrivate', 'user_id': _peerUserId},
            'permissions': {
              '@type': 'chatPermissions',
              'can_send_basic_messages': true,
            },
            'last_message': _history().last,
          },
          'getUser' => {
            '@type': 'user',
            'id': _peerUserId,
            'first_name': 'Peer',
            'last_name': '',
            'type': {'@type': 'userTypeRegular'},
          },
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
          'getConnectionState' => {'@type': 'connectionStateReady'},
          'getChatHistory' => {
            '@type': 'messages',
            'messages': _history().reversed.toList(),
          },
          'getMessages' => _messagesResponse(request),
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  Future<void> pumpChat(WidgetTester tester, int chatId) async {
    _chatId = chatId;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({
      'showChannelsTab': false,
      'showMomentsTab': false,
      'communitiesEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AppLocaleController>.value(
            value: AppLocaleController(prefs),
          ),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
            // The bug was mobile-only: the reference client washes the
            // destination on a phone as well as on a desktop.
            platform: TargetPlatform.android,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatView(chatId: _chatId, title: 'Reply chat'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Pumps frame by frame until the reply jump has landed and washed the
  /// destination. The jump awaits layout frames and runs a 220 ms scroll
  /// animation, so its end cannot be predicted from a single duration.
  Future<void> pumpUntilWashed(WidgetTester tester) async {
    for (var frame = 0; frame < 150; frame++) {
      if (_highlightOf(_targetId).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Taps a reply marker, pinning first that the row is actually on screen (a
  /// marker scrolled out of the pane would tap the wrong place).
  Future<void> tapReplyMarker(WidgetTester tester, int messageId) async {
    final marker = _replyMarkerOf(messageId);
    expect(marker, findsOneWidget, reason: 'message $messageId has a marker');
    expect(
      _onScreen(tester, marker),
      isTrue,
      reason: 'the marker is on screen',
    );
    await tester.tap(marker);
  }

  testWidgets('a reply jump washes its destination on Android', (tester) async {
    await pumpChat(tester, 950);
    final brand = AppTheme.brand;
    expect(
      _highlightOf(_targetId),
      findsNothing,
      reason: 'nothing is washed before the jump',
    );
    expect(
      _onScreen(tester, _bubbleOf(_targetId)),
      isFalse,
      reason: 'the quoted message starts above the loaded viewport',
    );

    await tapReplyMarker(tester, _bottomId);
    await pumpUntilWashed(tester);

    expect(
      _highlightOf(_targetId),
      findsOneWidget,
      reason: 'a phone reply jump must mark the message it lands on',
    );
    expect(
      _onScreen(tester, _bubbleOf(_targetId)),
      isTrue,
      reason: 'the jump scrolled the quoted message into view',
    );
    expect(_targetWash(tester, _targetId), brand.withValues(alpha: 0.18));
    expect(_paintedWash(tester, _targetId), brand.withValues(alpha: 0.18));
    expect(
      tester.widget<AnimatedContainer>(_highlightOf(_targetId)).duration,
      const Duration(milliseconds: 300),
      reason: 'the wash fades over 300 ms',
    );

    // Still washed past the old 650 ms desktop hold. The row is gone from the
    // tree entirely if the highlight never starts, so this also pins the hold.
    await tester.pump(const Duration(milliseconds: 850));
    expect(
      _paintedWash(tester, _targetId),
      brand.withValues(alpha: 0.18),
      reason: 'the wash holds for the full 1000 ms',
    );

    // 1000 ms in, the wash turns toward transparent: the widget target is 0
    // while the painted colour is still catching up.
    await tester.pump(const Duration(milliseconds: 200));
    expect(_targetWash(tester, _targetId), brand.withValues(alpha: 0));
    // The fade controller starts on the frame after the state change; give it
    // one tick at zero, then read the mid-fade colour.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final fading = _paintedWash(tester, _targetId);
    expect(fading, isNotNull);
    expect(
      fading!.a,
      greaterThan(0),
      reason: 'the wash is still visible while it fades',
    );
    expect(fading.a, lessThan(0.18));

    // After the fade the id clears and the wrapper leaves the row.
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      _highlightOf(_targetId),
      findsNothing,
      reason: 'the cleared highlight drops the row wash entirely',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a second reply jump restarts the wash timers', (tester) async {
    await pumpChat(tester, 951);
    final brand = AppTheme.brand;
    await tapReplyMarker(tester, _bottomId);
    await pumpUntilWashed(tester);
    expect(_highlightOf(_targetId), findsOneWidget);

    // Just short of the hold, jump again through the reply sitting under the
    // target: both jumps wash the same row, so only the timers distinguish
    // the second tap.
    await tester.pump(const Duration(milliseconds: 700));
    expect(_paintedWash(tester, _targetId), brand.withValues(alpha: 0.18));

    await tapReplyMarker(tester, _aboveId);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 1100 ms after the first tap the first wash would be fading out; the
    // restarted hold keeps the row fully washed.
    expect(
      _targetWash(tester, _targetId),
      brand.withValues(alpha: 0.18),
      reason: 'a second tap restarts the hold instead of inheriting the first',
    );
    expect(_paintedWash(tester, _targetId), brand.withValues(alpha: 0.18));

    // Let the restarted wash run its course so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_highlightOf(_targetId), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('disposing the chat mid-wash cancels the highlight timers', (
    tester,
  ) async {
    await pumpChat(tester, 952);
    await tapReplyMarker(tester, _bottomId);
    await pumpUntilWashed(tester);
    expect(_highlightOf(_targetId), findsOneWidget);

    // Dispose inside the 1000 ms hold and end the test without advancing the
    // clock: flutter_test fails on any timer left pending after the tree is
    // torn down, so this only passes when dispose cancels both timers.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
