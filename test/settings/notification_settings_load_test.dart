//
//  notification_settings_load_test.dart
//
//  Opening Notifications used to run a serial chain — three scope round
//  trips, each followed by an exception scan, then the saved sounds, then
//  getCurrentState and the stories scan — and only then paint the rows. On a
//  slow link the screen sat on a spinner for seconds. The rows now need only
//  the three independent scope payloads (issued together) and the rest
//  decorates them as it lands.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/notification_settings_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _private = 'notificationSettingsScopePrivateChats';
const _group = 'notificationSettingsScopeGroupChats';

const _scopePayload = <String, dynamic>{
  '@type': 'scopeNotificationSettings',
  'mute_for': 0,
  'sound_id': 0,
  'show_preview': true,
  'use_default_mute_stories': true,
  'mute_stories': false,
  'story_sound_id': 0,
  'show_story_sender': true,
  'disable_pinned_message_notifications': false,
  'disable_mention_notifications': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic> request)
  query;
  final requests = <String>[];

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        accountUserId: 1,
        query: (request) {
          requests.add(request['@type'] as String);
          return query(request);
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

  setUp(() {
    requests.clear();
    query = (request) async => const {'@type': 'ok'};
  });

  Future<void> pumpView(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const NotificationSettingsView(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the rows paint before the exception counts and state land', (
    tester,
  ) async {
    // Everything except the scope payloads stays unanswered: the counts, the
    // saved sounds and getCurrentState.
    final pending = Completer<Map<String, dynamic>>();
    query = (request) async {
      if (request['@type'] == 'getScopeNotificationSettings') {
        return _scopePayload;
      }
      return pending.future;
    };

    await pumpView(tester);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('notification-telegram-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notification-scope-$_private')),
      findsOneWidget,
    );

    pending.complete(const {'@type': 'ok'});
    await tester.pumpAndSettle();
  });

  testWidgets('the three scope round trips are issued together', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    query = (request) async {
      if (request['@type'] == 'getScopeNotificationSettings') {
        return gate.future;
      }
      return const {'@type': 'ok'};
    };

    await pumpView(tester);
    await tester.pump();

    expect(
      requests.where((type) => type == 'getScopeNotificationSettings').length,
      3,
      reason: 'the scopes are independent; a serial chain waits three times',
    );
    expect(
      find.byKey(const ValueKey('notification-scope-$_group')),
      findsNothing,
      reason: 'rows wait for the payloads they display',
    );

    gate.complete(_scopePayload);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notification-scope-$_group')),
      findsOneWidget,
    );
  });
}
