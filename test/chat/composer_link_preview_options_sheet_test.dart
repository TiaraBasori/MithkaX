//
//  composer_link_preview_options_sheet_test.dart
//
//  The link-preview panel mirrors the reply-options sheet: a titled card with
//  the link in the preview slot, full-width rows whose labels flip with the
//  state they produce on tap, a position row only while the preview is on, and
//  a red row that turns the preview off and closes.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/composer_link_preview_options_sheet.dart';
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

void main() {
  testWidgets('the panel shows the link and the stateful rows', (tester) async {
    await _pump(tester);
    expect(
      find.byKey(const ValueKey('composerLinkPreviewOptionsSheet')),
      findsOneWidget,
    );
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://example.com/story/one'), findsOneWidget);
    // The toggle row and the red remove row carry the same wording.
    expect(find.text('Hide link preview'), findsNWidgets(2));
    expect(find.text('Preview below the text'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composerLinkPreviewOptionRemove')),
      findsOneWidget,
    );
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
    await tester.tap(
      find.byKey(const ValueKey('composerLinkPreviewOptionDisable')),
    );
    await tester.pump();
    expect(changes, [false]);
    // The label and icon now offer the opposite action, and the position row
    // (which only applies to a visible preview) is gone.
    expect(find.text('Show link preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composerLinkPreviewOptionPosition')),
      findsNothing,
    );
  });

  testWidgets('the red row turns the preview off and closes', (tester) async {
    final changes = <bool>[];
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
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
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('composerLinkPreviewOptionRemove')),
    );
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(popped, isTrue);
  });
}
