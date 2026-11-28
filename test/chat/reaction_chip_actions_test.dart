//
//  reaction_chip_actions_test.dart
//
//  The reaction pill is ONE target: a tap on the emoji, on the number or on
//  the padding toggles the bucket. The reactor list is only the long press,
//  and only where Telegram lets this account see who reacted — a channel's
//  reactions are anonymous, so its long press must do nothing at all.
//
//  The chip also draws the reader's own face from the pane's identity the
//  moment the optimistic toggle prepends them to the bucket.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_reaction_chips.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _meId = 1;

ChatMessage _message({
  int chatId = -1001234567890,
  List<MessageReaction> reactions = const [],
}) {
  final message = ChatMessage(
    id: 5,
    chatId: chatId,
    isOutgoing: false,
    senderId: 9,
    text: 'hello',
    date: 1700000000,
    contentType: 'messageText',
  );
  message.reactions = reactions;
  return message;
}

Future<void> _pump(
  WidgetTester tester,
  ChatMessage message, {
  ValueChanged<MessageReaction>? onToggle,
  void Function(ChatMessage message, MessageReaction reaction)? onShowUsers,
  bool canSeeReactorList = true,
  int? meId = _meId,
  String meName = 'Me',
}) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: MessageReactionChips(
              message: message,
              outgoing: false,
              onToggle: onToggle,
              onShowUsers: onShowUsers,
              canSeeReactorList: canSeeReactorList,
              meId: meId,
              meName: meName,
              peerTitle: 'Alice',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// A group bucket big enough to keep its count, so the number is on screen.
const _bigGroupBucket = [MessageReaction(emoji: '👍', count: 4, chosen: false)];

void main() {
  testWidgets('tapping the count toggles the reaction, never the list', (
    tester,
  ) async {
    final toggled = <MessageReaction>[];
    final shown = <MessageReaction>[];
    await _pump(
      tester,
      _message(reactions: _bigGroupBucket),
      onToggle: toggled.add,
      onShowUsers: (_, reaction) => shown.add(reaction),
    );

    await tester.tap(find.text('4'));
    await tester.pump();

    expect(toggled, hasLength(1));
    expect(toggled.single.emoji, '👍');
    expect(shown, isEmpty, reason: 'the number no longer opens the panel');
  });

  testWidgets('tapping the emoji toggles the reaction', (tester) async {
    final toggled = <MessageReaction>[];
    final shown = <MessageReaction>[];
    await _pump(
      tester,
      _message(reactions: _bigGroupBucket),
      onToggle: toggled.add,
      onShowUsers: (_, reaction) => shown.add(reaction),
    );

    await tester.tap(find.text('👍'));
    await tester.pump();

    expect(toggled, hasLength(1));
    expect(toggled.single.emoji, '👍');
    expect(shown, isEmpty);
  });

  testWidgets('a long press opens the reactor list', (tester) async {
    final toggled = <MessageReaction>[];
    final shown = <MessageReaction>[];
    await _pump(
      tester,
      _message(reactions: _bigGroupBucket),
      onToggle: toggled.add,
      onShowUsers: (_, reaction) => shown.add(reaction),
    );

    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('reactionChip-5-emoji:👍')),
          )
          .onLongPress,
      isNotNull,
    );
    await tester.longPress(
      find.byKey(const ValueKey('reactionChip-5-emoji:👍')),
    );
    await tester.pump();

    expect(shown, hasLength(1));
    expect(shown.single.emoji, '👍');
    expect(toggled, isEmpty, reason: 'a long press is not a toggle');
  });

  testWidgets('long press does nothing where the list is anonymous', (
    tester,
  ) async {
    final shown = <MessageReaction>[];
    await _pump(
      tester,
      // A channel: TDLib reports can_get_added_reactions = false.
      _message(reactions: _bigGroupBucket),
      onToggle: (_) {},
      onShowUsers: (_, reaction) => shown.add(reaction),
      canSeeReactorList: false,
    );

    // No long-press recognizer is attached at all, so the gesture can never
    // reach the list — holding the pill degrades to releasing a tap.
    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('reactionChip-5-emoji:👍')),
          )
          .onLongPress,
      isNull,
    );
    await tester.longPress(
      find.byKey(const ValueKey('reactionChip-5-emoji:👍')),
    );
    await tester.pump();

    expect(shown, isEmpty);
  });

  testWidgets('a group bucket with the reader in it draws the avatar stack', (
    tester,
  ) async {
    await _pump(
      tester,
      _message(
        reactions: const [
          MessageReaction(
            emoji: '❤️',
            count: 2,
            chosen: true,
            // The optimistic toggle prepends the reader, so the chip must
            // paint their face straight from the pane's identity.
            reactors: [MessageReactor(senderId: _meId)],
          ),
        ],
      ),
    );

    final stack = find.byKey(const ValueKey('reactionAvatars-5-emoji:❤️'));
    expect(stack, findsOneWidget);
    expect(
      find.descendant(of: stack, matching: find.byType(PhotoAvatar)),
      findsOneWidget,
    );
    expect(find.text('2', findRichText: true), findsNothing);
  });
}
