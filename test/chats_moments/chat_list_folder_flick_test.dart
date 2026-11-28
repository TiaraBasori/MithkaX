//
//  chat_list_folder_flick_test.dart
//
//  exteraless switches folders on a short, fast flick even when the finger
//  never travelled the drag distance (DialogsActivity checks the release
//  velocity). mithka only armed the pager at kTouchSlop, so a quick short
//  swipe stayed a tap and opened the chat under the finger.
//

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the flick threshold matches exteraless converted to logical pixels',
    () {
      expect(
        chatListFolderFlickVelocity(devicePixelRatio: 1, landscape: false),
        850,
      );
      expect(
        chatListFolderFlickVelocity(devicePixelRatio: 1, landscape: true),
        1250,
      );
      expect(
        chatListFolderFlickVelocity(devicePixelRatio: 2.5, landscape: false),
        340,
        reason:
            'Android velocities are physical pixels; Flutter reports logical',
      );
    },
  );

  test('a fast short horizontal flick counts', () {
    expect(
      chatListFolderFlick(
        travel: const Offset(-12, 2),
        velocity: const Offset(-900, 40),
        velocityThreshold: 340,
      ),
      isTrue,
    );
  });

  test('a slow short drag does not', () {
    expect(
      chatListFolderFlick(
        travel: const Offset(-12, 2),
        velocity: const Offset(-200, 40),
        velocityThreshold: 340,
      ),
      isFalse,
    );
  });

  test('a vertical flick does not switch folders', () {
    expect(
      chatListFolderFlick(
        travel: const Offset(-12, 30),
        velocity: const Offset(-900, 1200),
        velocityThreshold: 340,
      ),
      isFalse,
      reason: 'the list must keep its vertical scroll',
    );
  });

  test('a diagonal flick stays with the list', () {
    expect(
      chatListFolderFlick(
        travel: const Offset(-12, 8),
        velocity: const Offset(-520, 560),
        velocityThreshold: 340,
      ),
      isFalse,
      reason:
          'the pager must only arm from a clearly horizontal contact; a '
          'diagonal thumb drift is a scroll',
    );
  });

  test('a diagonal release stays with the list', () {
    final decision = chatListSwipeDecision(
      mode: ChatListSwipeMode.switchFolders,
      peakPointerCount: 1,
      pointerDeltas: const [Offset(-90, 80)],
    );
    expect(decision.action, ChatListSwipeAction.none);
  });

  test('a clearly horizontal release still switches folders', () {
    final decision = chatListSwipeDecision(
      mode: ChatListSwipeMode.switchFolders,
      peakPointerCount: 1,
      pointerDeltas: const [Offset(-90, 40)],
    );
    expect(decision.action, ChatListSwipeAction.switchFolders);
  });

  test('a steep swipe stays with the list', () {
    final decision = chatListSwipeDecision(
      mode: ChatListSwipeMode.switchFolders,
      peakPointerCount: 1,
      pointerDeltas: const [Offset(-70, 132)],
    );
    expect(decision.action, ChatListSwipeAction.none);
  });

  test('a stationary press cannot start the pager', () {
    expect(
      chatListFolderFlick(
        travel: const Offset(-2, 0),
        velocity: const Offset(-1600, 0),
        velocityThreshold: 340,
      ),
      isFalse,
    );
  });

  testWidgets('the live session reports a short flick before release', (
    tester,
  ) async {
    final session = ChatListSwipeSession();
    expect(
      session.pointerDown(
        pointer: 1,
        position: const Offset(200, 400),
        kind: ui.PointerDeviceKind.touch,
        mode: ChatListSwipeMode.switchFolders,
        timeStamp: Duration.zero,
      ),
      isTrue,
    );
    // Three samples: the framework's estimator needs at least three.
    session.pointerMove(
      pointer: 1,
      position: const Offset(196, 400),
      timeStamp: const Duration(milliseconds: 8),
    );
    session.pointerMove(
      pointer: 1,
      position: const Offset(190, 401),
      timeStamp: const Duration(milliseconds: 16),
    );
    expect(
      session.liveFlick(
        ChatListSwipeMode.switchFolders,
        velocityThreshold: 340,
      ),
      isTrue,
      reason: '10px in 16ms is a flick, well under the drag distance',
    );
    session.pointerEnd(
      pointer: 1,
      position: const Offset(190, 401),
      currentMode: ChatListSwipeMode.switchFolders,
      timeStamp: const Duration(milliseconds: 24),
    );
  });

  testWidgets('arming is strict, the moving drag keeps its drift tolerance', (
    tester,
  ) async {
    final session = ChatListSwipeSession();
    session.pointerDown(
      pointer: 1,
      position: const Offset(200, 400),
      kind: ui.PointerDeviceKind.touch,
      mode: ChatListSwipeMode.switchFolders,
      timeStamp: Duration.zero,
    );
    // A clearly horizontal start past the activation distance: this is the only
    // way the pager is allowed to arm.
    session.pointerMove(
      pointer: 1,
      position: const Offset(170, 410),
      timeStamp: const Duration(milliseconds: 16),
    );
    expect(
      session.liveDecision(ChatListSwipeMode.switchFolders).action,
      ChatListSwipeAction.switchFolders,
    );
    // The finger drifts downward afterwards. The pager is already moving, so
    // the loose drift bias keeps the drag; the strict arming gate would have
    // called this a scroll.
    session.pointerMove(
      pointer: 1,
      position: const Offset(170, 440),
      timeStamp: const Duration(milliseconds: 32),
    );
    expect(
      session.liveDecision(ChatListSwipeMode.switchFolders).action,
      ChatListSwipeAction.none,
    );
    expect(
      session
          .liveDecision(
            ChatListSwipeMode.switchFolders,
            diagonalBias: chatListFolderDiagonalBias,
          )
          .action,
      ChatListSwipeAction.switchFolders,
    );
    session.pointerEnd(
      pointer: 1,
      position: const Offset(170, 440),
      currentMode: ChatListSwipeMode.switchFolders,
      timeStamp: const Duration(milliseconds: 48),
    );
  });

  testWidgets('a diagonal start never arms the pager', (tester) async {
    final session = ChatListSwipeSession();
    session.pointerDown(
      pointer: 1,
      position: const Offset(200, 400),
      kind: ui.PointerDeviceKind.touch,
      mode: ChatListSwipeMode.switchFolders,
      timeStamp: Duration.zero,
    );
    // 30 px right, 30 px down: a 45-degree thumb drift, i.e. a scroll.
    session.pointerMove(
      pointer: 1,
      position: const Offset(170, 430),
      timeStamp: const Duration(milliseconds: 16),
    );
    expect(
      session.liveDecision(ChatListSwipeMode.switchFolders).action,
      ChatListSwipeAction.none,
    );
    expect(
      session.liveFlick(
        ChatListSwipeMode.switchFolders,
        velocityThreshold: 340,
      ),
      isFalse,
    );
    session.pointerEnd(
      pointer: 1,
      position: const Offset(170, 430),
      currentMode: ChatListSwipeMode.switchFolders,
      timeStamp: const Duration(milliseconds: 32),
    );
  });

  testWidgets('a slow move under the distance is not a flick', (tester) async {
    final session = ChatListSwipeSession();
    session.pointerDown(
      pointer: 1,
      position: const Offset(200, 400),
      kind: ui.PointerDeviceKind.touch,
      mode: ChatListSwipeMode.switchFolders,
      timeStamp: Duration.zero,
    );
    // 10px over 200ms = 50px/s.
    session.pointerMove(
      pointer: 1,
      position: const Offset(196, 400),
      timeStamp: const Duration(milliseconds: 100),
    );
    session.pointerMove(
      pointer: 1,
      position: const Offset(190, 400),
      timeStamp: const Duration(milliseconds: 200),
    );
    expect(
      session.liveFlick(
        ChatListSwipeMode.switchFolders,
        velocityThreshold: 340,
      ),
      isFalse,
    );
    session.pointerEnd(
      pointer: 1,
      position: const Offset(190, 400),
      currentMode: ChatListSwipeMode.switchFolders,
      timeStamp: const Duration(milliseconds: 216),
    );
  });
}
