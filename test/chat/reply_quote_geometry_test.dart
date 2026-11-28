//
//  reply_quote_geometry_test.dart
//
//  The reply panel mirrors the reference client's `ReplyMessageLine`: it is
//  sized by its content (a short reply to a short message is a short panel,
//  never a full-width bar), the author is bold 14pt in the quoted colour, the
//  preview is 14pt, and the media thumbnail is a 34pt square.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String preview,
  String body = 'ok',
  TdFileRef? replyImage,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  final message =
      ChatMessage(
          id: 2,
          isOutgoing: false,
          text: body,
          date: 1,
          contentType: 'messageText',
          replyToMessageId: 1,
          replyToDate: 1,
          replyToImage: replyImage,
        )
        ..replyToSender = 'Ada'
        ..replyToPreview = preview;
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            peerTitle: 'Discussion',
            isGroup: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

late File _still;

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('reply-quote');
    _still = File('${dir.path}/still.jpg')..writeAsBytesSync([0, 1, 2]);
  });

  testWidgets('a short reply is a short panel, not a full-width bar', (
    tester,
  ) async {
    await _pump(tester, preview: 'yes');
    final panel = tester.getSize(
      find.byKey(const ValueKey('messageReplyQuote')),
    );
    final bubble = tester.getSize(
      find.byKey(const ValueKey('messageTextBubble-2')),
    );
    // The viewport is 360pt wide, so the bubble lane is 270. A two-word reply
    // panel must stay well under it and under the bubble it sits in.
    expect(panel.width, lessThan(200));
    expect(panel.width, lessThanOrEqualTo(bubble.width));
    // The bubble itself must hug too: an expanded panel would still stretch
    // the whole row.
    expect(bubble.width, lessThan(200));
  });

  testWidgets('the author is bold and the preview one step below the body', (
    tester,
  ) async {
    await _pump(tester, preview: 'yes');
    final texts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('messageReplyQuote')),
        matching: find.byType(RichText),
      ),
    );
    TextSpan? sender;
    for (final text in texts) {
      final root = text.text;
      if (root is! TextSpan) continue;
      for (final child in root.children ?? const <InlineSpan>[]) {
        if (child is TextSpan && (child.text ?? '').contains('Ada')) {
          sender = child;
        }
      }
    }
    expect(sender?.style?.fontWeight, FontWeight.w700);
    final preview = texts.firstWhere(
      (text) => text.text.toPlainText().contains('yes'),
    );
    expect(preview.text.style?.fontSize, 14);
  });

  testWidgets('the quoted photo is a 34pt square', (tester) async {
    await _pump(
      tester,
      preview: 'photo',
      replyImage: TdFileRef(id: 3, localPath: _still.path),
    );
    final thumb = tester.getSize(
      find.byKey(const ValueKey('messageReplyMediaPreview')),
    );
    expect(thumb, const Size(34, 34));
  });

  testWidgets('the marker and the body share one width', (tester) async {
    const body =
        'This is a long message body that has to wrap over several lines so '
        'the bubble reaches the lane width and the marker can follow it.';
    await _pump(tester, preview: 'yes', body: body);
    final panel = tester.getRect(
      find.byKey(const ValueKey('messageReplyQuote')),
    );
    final bubble = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-2')),
    );
    // The reference's reply line spans the bubble; the body sits in the same
    // box. Both edges line up instead of the marker floating in its own box.
    expect(panel.width, greaterThan(200));
    expect(panel.left, closeTo(bubble.left + 10, 1.5));
    expect(panel.right, closeTo(bubble.right - 10, 1.5));
  });

  testWidgets('a short marker never draws wider than its message', (
    tester,
  ) async {
    await _pump(tester, preview: 'yes', body: 'k');
    final panel = tester.getSize(
      find.byKey(const ValueKey('messageReplyQuote')),
    );
    final bubble = tester.getSize(
      find.byKey(const ValueKey('messageTextBubble-2')),
    );
    expect(panel.width, lessThan(bubble.width));
    // And the pair still hugs: no full-lane bar for two short lines.
    expect(bubble.width, lessThan(200));
  });
}
