//
//  composer_link_preview_options_sheet_test.dart
//
//  The link-preview panel mirrors the reply-options sheet: a titled card with
//  the link in the preview slot, an on/off row whose label flips with the state
//  it produces on tap, and two position rows that name the side the card is on
//  now — the current one checked — so no wording is ambiguous and no action is
//  duplicated.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/composer_link_preview_options_sheet.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

Future<List<bool>> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool above = true,
}) async {
  final enabledChanges = <bool>[];
  final positionChanges = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ComposerLinkPreviewOptionsSheet(
          url: 'https://example.com/story/one',
          enabled: enabled,
          showAboveText: above,
          onEnabledChanged: enabledChanges.add,
          onPositionChanged: positionChanges.add,
        ),
      ),
    ),
  );
  await tester.pump();
  return [enabledChanges.isNotEmpty, positionChanges.isNotEmpty];
}

Finder _row(String key) =>
    find.byKey(ValueKey('composerLinkPreviewOption$key'));

/// The trailing check on [row], if the row is the selected position.
bool _isChecked(WidgetTester tester, String key) {
  final icons = tester
      .widgetList<AppIcon>(
        find.descendant(of: _row(key), matching: find.byType(AppIcon)),
      )
      .toList();
  return icons.last.icon == HeroAppIcons.check;
}

void main() {
  testWidgets('the panel shows the link and the stateful rows', (tester) async {
    await _pump(tester);
    expect(
      find.byKey(const ValueKey('composerLinkPreviewOptionsSheet')),
      findsOneWidget,
    );
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://example.com/story/one'), findsOneWidget);
    // ONE off entry: the old sheet repeated this wording on a red remove row.
    expect(find.text('Hide link preview'), findsOneWidget);
    // Both sides are named; the one in force carries the check.
    expect(find.text('Preview above the text'), findsOneWidget);
    expect(find.text('Preview below the text'), findsOneWidget);
    expect(_isChecked(tester, 'Above'), isTrue);
    expect(_isChecked(tester, 'Below'), isFalse);
    expect(_row('Remove'), findsNothing);
  });

  testWidgets('the toggle flips its own label and reports at once', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposerLinkPreviewOptionsSheet(
            url: 'https://example.com',
            enabled: true,
            showAboveText: true,
            onEnabledChanged: changes.add,
            onPositionChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(_row('Disable'));
    await tester.pump();
    expect(changes, [false]);
    // The label and icon now offer the opposite action, and the position rows
    // (which only apply to a visible preview) are gone.
    expect(find.text('Show link preview'), findsOneWidget);
    expect(_row('Above'), findsNothing);
    expect(_row('Below'), findsNothing);
  });

  testWidgets('picking a side reports it and moves the check', (tester) async {
    final positions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposerLinkPreviewOptionsSheet(
            url: 'https://example.com',
            enabled: true,
            showAboveText: true,
            onEnabledChanged: (_) {},
            onPositionChanged: positions.add,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(_row('Below'));
    await tester.pump();
    expect(positions, [false]);
    expect(_isChecked(tester, 'Above'), isFalse);
    expect(_isChecked(tester, 'Below'), isTrue);

    // Tapping the side already in force is a no-op, not a second report.
    await tester.tap(_row('Below'));
    await tester.pump();
    expect(positions, [false]);
  });
}
