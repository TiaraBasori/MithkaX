//
//  chat_floating_date_test.dart
//
//  The reference client pins a date plate at the top of the transcript while
//  the list is scrolling, follows the topmost visible message, and fades the
//  plate out 500 ms after the scroll stops (ChatActivity.showFloatingDateView /
//  hideFloatingDateView). MithkaX had no such plate.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 5150;
const _peerId = 777;

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000000 + id * 21600,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': _peerId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'message $id'},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
          'getChat' => {
            '@type': 'chat',
            'id': _chatId,
            'type': {'@type': 'chatTypePrivate', 'user_id': _peerId},
            'title': 'Peer',
            'unread_count': 0,
          },
          'getUser' => {
            '@type': 'user',
            'id': _peerId,
            'first_name': 'Peer',
            'type': {'@type': 'userTypeRegular'},
          },
          'getChatHistory' =>
            request['only_local'] == true
                ? <String, dynamic>{'@type': 'messages', 'messages': []}
                : {
                    '@type': 'messages',
                    'messages': [
                      for (var id = 40; id >= 1; id--) _message(id),
                    ],
                  },
          'getConnectionState' => {'@type': 'connectionStateReady'},
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

  testWidgets('the date plate follows scrolling and fades out when it stops', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
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
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _chatId, title: 'Peer'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    final floating = find.byKey(const ValueKey('chat-floating-date'));
    expect(
      floating,
      findsNothing,
      reason: 'no plate before the transcript has been scrolled',
    );

    final transcript = find.byType(CustomScrollView);
    final gesture = await tester.startGesture(tester.getCenter(transcript));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 260));
    await tester.pump(const Duration(milliseconds: 16));

    expect(floating, findsOneWidget, reason: 'the plate appears while scrolling');
    final shown = tester.widget<AnimatedOpacity>(
      find.ancestor(of: floating, matching: find.byType(AnimatedOpacity)),
    );
    expect(shown.opacity, 1);
    final dateText = tester.widget<Text>(
      find.descendant(of: floating, matching: find.byType(Text)),
    );
    expect(dateText.data, isNotEmpty);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: floating, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      1,
      reason: 'the plate survives the reference client\'s 500 ms grace',
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: floating, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
      reason: 'the plate fades out 500 ms after the scroll stops',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
