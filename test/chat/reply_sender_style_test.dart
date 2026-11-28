//
//  reply_sender_style_test.dart
//
//  exteraless paints a reply line in the QUOTED author's peer colour — in both
//  directions — and scatters their reply-header emoji across the panel. That
//  emoji is the name colour's background custom emoji, NOT the account's
//  emoji status. The appearance switch can turn the styling off and leave a
//  plain theme-coloured marker.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/chat/stickers/custom_emoji.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_name_colors.dart';
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
          _ => <String, dynamic>{'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() => updates.close());

  Future<ThemeController> pumpReply(
    WidgetTester tester, {
    required ChatMessage message,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    tester.view
      ..physicalSize = const Size(1260, 2700)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
    return theme;
  }

  ChatMessage replyMessage() =>
      ChatMessage(
          id: 5,
          isOutgoing: false,
          text: '谢谢',
          date: 10,
          contentType: 'messageText',
          replyToMessageId: 1,
          replyToDate: 8,
          replyToSenderAccentColorId: 2,
          replyToSenderBackgroundEmojiId: 600,
          // Decoy: the quoted author's emoji STATUS must never paint the
          // marker; only the name colour's background emoji does.
          replyToSenderEmojiStatusId: 611,
          replyToSenderIsPremium: true,
        )
        ..replyToSender = 'Ada'
        ..replyToPreview = 'the quoted line';

  /// The colour the marker should use for [message]: the quoted author's name
  /// colour at the given accent id. `theme: null` matches the default test
  /// theme, which has no cloud theme bound.
  Color accentColorFor(ChatMessage message) => messageNameColorForSender(
    theme: null,
    accentColorId: message.replyToSenderAccentColorId,
    showNameColors: true,
    nameColorsDisabledFallback: Colors.black,
  );

  BoxDecoration quoteDecoration(WidgetTester tester) =>
      tester
              .widget<Container>(
                find.byKey(const ValueKey('messageReplyQuote')),
              )
              .decoration!
          as BoxDecoration;

  Color quoteRule(WidgetTester tester) =>
      (quoteDecoration(tester).border! as Border).left.color;

  Finder quoteDescendant(Finder matching) => find.descendant(
    of: find.byKey(const ValueKey('messageReplyQuote')),
    matching: matching,
  );

  /// The RichText that renders the quoted author's name.
  RichText authorText(WidgetTester tester, String name) => tester
      .widgetList<RichText>(quoteDescendant(find.byType(RichText)))
      .firstWhere((text) => text.text.toPlainText().contains(name));

  testWidgets('the marker takes the quoted author colour and header emoji', (
    tester,
  ) async {
    final message = replyMessage();
    await pumpReply(tester, message: message);

    final senderColor = accentColorFor(message);
    expect(quoteDecoration(tester).color, senderColor.withValues(alpha: 0.10));
    expect(quoteRule(tester), senderColor);
    expect(authorText(tester, 'Ada').text.style?.color, senderColor);

    // The reply-header emoji is a SCATTER of small glyphs, not one big
    // watermark: seven entries without an explicit quote.
    final watermark = find.byKey(
      const ValueKey('messageReplySenderEmojiStatus'),
    );
    expect(watermark, findsOneWidget);
    expect(
      find.descendant(of: watermark, matching: find.byType(CustomEmojiView)),
      findsNWidgets(7),
    );
    // The quoted author's emoji status is not the reply-header emoji.
    expect(quoteDescendant(find.byType(StatusEmojiView)), findsNothing);
    expect(
      find.byKey(const ValueKey('messageReplyNavigateUpIcon')),
      findsNothing,
    );
    final previews = tester.widgetList<RichText>(
      quoteDescendant(find.byType(RichText)),
    );
    expect(
      previews.any(
        (text) =>
            text.maxLines == 1 &&
            // The reference client's reply text is one step below the body
            // size; the panel used to run it at full message size.
            text.text.style?.fontSize == AppTextSize.callout,
      ),
      isTrue,
    );
  });

  testWidgets('an explicit quote adds the two quote-only glyphs', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 8,
      isOutgoing: false,
      text: 'agreed',
      date: 12,
      contentType: 'messageText',
      replyToMessageId: 1,
      replyToDate: 8,
      replyToSenderAccentColorId: 2,
      replyToSenderBackgroundEmojiId: 600,
      replyToQuote: const MessageTextQuote(
        text: 'the quoted part',
        position: 0,
      ),
    )..replyToSender = 'Ada';
    await pumpReply(tester, message: message);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('messageReplySenderEmojiStatus')),
        matching: find.byType(CustomEmojiView),
      ),
      findsNWidgets(9),
    );
  });

  testWidgets('the scatter uses the reference glyph size and dimming', (
    tester,
  ) async {
    await pumpReply(tester, message: replyMessage());
    // ReplyMessageLine.drawBackground sets drawable bounds to ±dp(10)*scale,
    // i.e. a 20dp glyph at scale 1, and dims it by 0.30 * its own alpha
    // multiplier (the fifth entry carries 0.3).
    final first = find.byKey(
      const ValueKey('messageReplySenderEmojiStatusGlyph0'),
    );
    expect(tester.getSize(first), const Size.square(20));
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: first, matching: find.byType(Opacity)),
          )
          .opacity,
      closeTo(0.30, 0.001),
    );
    final fifth = find.byKey(
      const ValueKey('messageReplySenderEmojiStatusGlyph4'),
    );
    expect(tester.getSize(fifth).width, closeTo(20 * 1.03, 0.001));
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: fifth, matching: find.byType(Opacity)),
          )
          .opacity,
      closeTo(0.30 * 0.3, 0.001),
    );
  });

  testWidgets('the emoji scatter never changes the panel geometry', (
    tester,
  ) async {
    await pumpReply(tester, message: replyMessage());
    final withEmoji = tester.getSize(
      find.byKey(const ValueKey('messageReplyQuote')),
    );
    await pumpReply(
      tester,
      message: replyMessage()..replyToSenderBackgroundEmojiId = 0,
    );
    final withoutEmoji = tester.getSize(
      find.byKey(const ValueKey('messageReplyQuote')),
    );
    expect(withEmoji, withoutEmoji);
  });

  testWidgets('an outgoing reply takes the quoted author colour too', (
    tester,
  ) async {
    // exteraless does NOT override a reply colour once the message is ours:
    // Ada's accent paints our marker as well, and her reply-header emoji
    // stays. This used to fall back to the bubble ink.
    final message =
        ChatMessage(
            id: 6,
            isOutgoing: true,
            text: 'thanks',
            date: 10,
            contentType: 'messageText',
            replyToMessageId: 1,
            replyToDate: 8,
            replyToSenderAccentColorId: 2,
            replyToSenderBackgroundEmojiId: 600,
            replyToSenderIsPremium: true,
          )
          ..replyToSender = 'Ada'
          ..replyToPreview = 'the quoted line';
    await pumpReply(tester, message: message);

    final senderColor = accentColorFor(message);
    expect(quoteDecoration(tester).color, senderColor.withValues(alpha: 0.10));
    expect(quoteRule(tester), senderColor);
    expect(authorText(tester, 'Ada').text.style?.color, senderColor);
    expect(
      find.byKey(const ValueKey('messageReplySenderEmojiStatus')),
      findsOneWidget,
    );
  });

  testWidgets('a reply quoting MY message takes my accent, not my status', (
    tester,
  ) async {
    // The quoted message is ours (isOutgoing upstream): the view model stamps
    // it with our own accent from getMe, so the marker carries our name
    // colour. Our emoji status is irrelevant to it.
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: 'that was quick',
            date: 12,
            contentType: 'messageText',
            replyToMessageId: 3,
            replyToDate: 11,
            replyToSenderAccentColorId: 4,
            replyToSenderBackgroundEmojiId: 700,
            replyToSenderEmojiStatusId: 612,
            replyToSenderIsPremium: true,
          )
          ..replyToSender = 'Me'
          ..replyToPreview = 'my own line';
    await pumpReply(tester, message: message);

    final myColor = accentColorFor(message);
    expect(quoteDecoration(tester).color, myColor.withValues(alpha: 0.10));
    expect(quoteRule(tester), myColor);
    expect(authorText(tester, 'Me').text.style?.color, myColor);
    expect(quoteDescendant(find.byType(StatusEmojiView)), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('messageReplySenderEmojiStatus')),
        matching: find.byType(CustomEmojiView),
      ),
      findsNWidgets(7),
    );
  });

  testWidgets('an emoji status alone paints nothing', (tester) async {
    final message =
        ChatMessage(
            id: 9,
            isOutgoing: false,
            text: 'ok',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 1,
            replyToDate: 1,
            replyToSenderEmojiStatusId: 611,
          )
          ..replyToSender = 'Ada'
          ..replyToPreview = 'the quoted line';
    await pumpReply(tester, message: message);

    // No resolved accent: the theme's reply line, and no emoji at all.
    expect(
      quoteDecoration(tester).color,
      AppTheme.brand.withValues(alpha: 0.10),
    );
    expect(
      find.byKey(const ValueKey('messageReplySenderEmojiStatus')),
      findsNothing,
    );
    expect(quoteDescendant(find.byType(StatusEmojiView)), findsNothing);
  });

  testWidgets('turning the switch off leaves a plain theme colour', (
    tester,
  ) async {
    final theme = await pumpReply(tester, message: replyMessage());
    final styled = quoteDecoration(tester).color;

    theme.replyQuoteSenderStyle = false;
    await tester.pump();

    expect(quoteDecoration(tester).color, isNot(styled));
    expect(
      quoteDecoration(tester).color,
      AppTheme.brand.withValues(alpha: 0.10),
    );
    expect(
      find.byKey(const ValueKey('messageReplySenderEmojiStatus')),
      findsNothing,
    );
  });
}
