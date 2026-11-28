//
//  storage_usage_localization_test.dart
//
//  Data & storage is the settings hub's StorageUsageView. Two reports meet
//  here: its media-retention / cache-limit values were hard-coded English, and
//  the reset-database row was added to GeneralSettingsView — a page no settings
//  destination opens — so it never appeared in 数据与存储.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/downloads_storage/storage_usage_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
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
          'getStorageStatisticsFast' => <String, dynamic>{
            '@type': 'storageStatisticsFast',
            'files_size': 1024,
            'file_count': 2,
            'database_size': 0,
            'language_pack_database_size': 0,
            'log_size': 0,
          },
          'getStorageStatistics' => <String, dynamic>{
            '@type': 'storageStatistics',
            'size': 1024,
            'count': 2,
            'by_chat': <Map<String, dynamic>>[],
            'by_file_type': <Map<String, dynamic>>[],
          },
          _ => <String, dynamic>{'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  Future<void> pumpStorage(
    WidgetTester tester, {
    required Locale locale,
  }) async {
    SharedPreferences.setMockInitialValues({
      'storage.retentionSeconds': 259200,
      'storage.maxCacheBytes': 1073741824,
    });
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1200, 4800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const StorageUsageView(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the retention and cache values follow the app locale', (
    tester,
  ) async {
    await pumpStorage(tester, locale: const Locale('zh'));

    expect(find.text('媒体文件保留时间'), findsOneWidget);
    expect(find.text('3 天'), findsOneWidget);
    expect(find.text('缓存大小限制'), findsOneWidget);
    expect(find.text('1 GB'), findsOneWidget);
    // The old hard-coded English must be gone.
    expect(find.text('3 days'), findsNothing);
    expect(find.text('Forever'), findsNothing);
    expect(find.text('No limit'), findsNothing);
  });

  testWidgets('reset database is reachable from Data & storage', (
    tester,
  ) async {
    await pumpStorage(tester, locale: const Locale('zh'));

    expect(
      find.byKey(const ValueKey('storage-reset-database')),
      findsOneWidget,
    );
    expect(find.text('重置数据库'), findsOneWidget);
  });
}
