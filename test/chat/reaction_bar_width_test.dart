//
//  reaction_bar_width_test.dart
//
//  The reaction strip hugs what it shows. A message whose availability lists
//  two reactions used to open a screen-wide bar with two emoji spread apart
//  and a chevron that reopened the same set. The strip now sizes itself from
//  its slots, and the expand button disappears entirely when one row already
//  lists every reaction the message allows.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_action_menu.dart';
import 'package:mithka/chat/messages/quick_reaction_choice.dart';
import 'package:mithka/theme/app_theme.dart';

List<QuickReactionChoice> _choices(int count) => [
  for (var i = 0; i < count; i++) QuickReactionChoice.emoji('😀'),
];

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a short strip hugs its slots instead of the screen width', (
    tester,
  ) async {
    await _pump(
      tester,
      QuickReactionBar(
        reactions: _choices(2),
        onReaction: (_) {},
        onExpand: () {},
      ),
    );
    final bar = tester.getSize(
      find.byKey(const ValueKey('quick-reaction-bar')),
    );
    // Two emoji plus the expand slot, the 8pt padding on both sides.
    expect(
      bar.width,
      2 * QuickReactionBar.slotWidth + QuickReactionBar.slotWidth + 16,
    );
    expect(bar.width, lessThan(360 - 24));
  });

  testWidgets('no expand button while every reaction is already shown', (
    tester,
  ) async {
    await _pump(
      tester,
      QuickReactionBar(
        reactions: _choices(3),
        onReaction: (_) {},
        onExpand: () {},
        showExpand: false,
      ),
    );
    expect(find.byKey(const ValueKey('quick-reaction-expand')), findsNothing);
    final bar = tester.getSize(
      find.byKey(const ValueKey('quick-reaction-bar')),
    );
    expect(bar.width, 3 * QuickReactionBar.slotWidth + 16);
  });

  test('capacity follows the lane width, capped at the fitted maximum', () {
    // 360dp phone: (336 - 16) / 40 = 8 slots.
    expect(QuickReactionBar.fittedCapacity(336), 8);
    // A narrow pane still fits at least one slot.
    expect(QuickReactionBar.fittedCapacity(30), 1);
    // Tablets stop at the designed maximum instead of stretching the row.
    expect(
      QuickReactionBar.fittedCapacity(1200),
      QuickReactionBar.maxFittedButtonCount,
    );
  });
}
