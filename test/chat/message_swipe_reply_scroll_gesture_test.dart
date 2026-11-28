//
//  message_swipe_reply_scroll_gesture_test.dart
//
//  A transcript row owns a horizontal swipe-to-reply recognizer. A plain
//  HorizontalDragGestureRecognizer accepts as soon as |dx| crosses the touch
//  slop, so a scroll that drifts sideways loses its contact to the row and the
//  list stutters. The row's recognizer is axis-locked: it only takes the
//  pointer when the travel is clearly sideways, leaving vertical scrolling the
//  high-priority gesture.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_swipe_reply.dart';

Widget _transcript({
  required ScrollController controller,
  required VoidCallback onReply,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView.builder(
        controller: controller,
        itemCount: 40,
        itemBuilder: (context, index) => MessageSwipeReplyRow(
          key: ValueKey('row-$index'),
          onReply: onReply,
          child: SizedBox(
            height: 80,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 220,
                height: 60,
                color: const Color(0xFF335577),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a scroll that drifts sideways still scrolls the transcript', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var replies = 0;
    await tester.pumpWidget(
      _transcript(controller: controller, onReply: () => replies++),
    );

    // A real thumb: one event that already leans left by a hair more than it
    // leans down, then a plain scroll. The horizontal recognizer used to take
    // that first event (|dx| crossed the slop) and the list never moved.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-2'))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-19, -17));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      controller.offset,
      greaterThan(120),
      reason: 'the vertical drag must keep the transcript scrolling',
    );
    expect(replies, 0);
  });

  testWidgets('a deliberate sideways swipe still replies', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var replies = 0;
    await tester.pumpWidget(
      _transcript(controller: controller, onReply: () => replies++),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-2'))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-24, 2));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(replies, 1);
    expect(controller.offset, 0);
  });
}
