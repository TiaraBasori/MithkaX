//
//  reset_database_settings_row_test.dart
//
//  “重置数据库” ends the process once the wipe lands: every page in memory was
//  built from the database that was just deleted, so repainting the settings
//  screen left the account looking signed out until the next launch. The row
//  also has to keep running (and say what failed) when an account could not be
//  reset, and on iOS, which cannot terminate itself.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/downloads_storage/local_database_reset.dart';
import 'package:mithka/settings/downloads_storage/reset_database_settings_row.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRow(
    WidgetTester tester, {
    required Future<LocalDatabaseResetResult> Function() runReset,
    required Future<bool> Function() quitApp,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: ResetDatabaseSettingsRow(
              runReset: runReset,
              quitApp: quitApp,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings-reset-database')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The confirm card promises the exit before the wipe runs.
    expect(find.textContaining('应用会完全退出'), findsOneWidget);
    await tester.tap(
      find.text(
        AppStringKeys.historyClearAction.l10n(
          tester.element(find.byType(ResetDatabaseSettingsRow)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a clean reset ends the process instead of repainting', (
    tester,
  ) async {
    var resets = 0;
    var quits = 0;
    await pumpRow(
      tester,
      runReset: () async {
        resets += 1;
        return const LocalDatabaseResetResult(databasesReset: 1, failures: []);
      },
      quitApp: () async {
        quits += 1;
        return true;
      },
    );

    await confirm(tester);

    expect(resets, 1);
    expect(quits, 1);
  });

  testWidgets('a partial failure keeps the app open and says so', (
    tester,
  ) async {
    var quits = 0;
    await pumpRow(
      tester,
      runReset: () async => const LocalDatabaseResetResult(
        databasesReset: 1,
        failures: ['account slot 2: timeout'],
      ),
      quitApp: () async {
        quits += 1;
        return true;
      },
    );

    await confirm(tester);

    expect(quits, 0);
    expect(find.text('部分账号未能重置，其本地数据库保持原样。'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('a platform that cannot exit stays usable', (tester) async {
    var quits = 0;
    await pumpRow(
      tester,
      runReset: () async =>
          const LocalDatabaseResetResult(databasesReset: 1, failures: []),
      quitApp: () async {
        quits += 1;
        return false;
      },
    );

    await confirm(tester);

    expect(quits, 1);
    expect(find.text('数据库已重置'), findsOneWidget);
    expect(find.byType(ResetDatabaseSettingsRow), findsOneWidget);
    await drainToast(tester);
  });
}
