//
//  music_player_back_swipe_test.dart
//
//  The player's three surfaces all take horizontal drags: the expanded bar
//  (left dismisses, right minimises), the split shell's mini card, and the
//  floating collapsed pill. A rightward drag on any of them used to ALSO arm
//  the chat's right-swipe-back — the page's back swipe is a raw pointer
//  listener that never loses the arena — so minimising the player popped the
//  chat instead. Each gesture-owning subtree is now marked
//  ExcludeFromBackSwipe, which the page skips at pointer-down.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media/music_player_controller.dart';
import 'package:mithka/components/full_page_back_swipe.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatMessage track() => ChatMessage(
    id: 7,
    isOutgoing: false,
    text: '',
    date: 1,
    chatId: 9,
    // No cover: the artwork goes through TDImage, whose loader arms timers
    // this gesture test has no transport to answer.
    music: MessageMusic(
      title: 'The Peak',
      performer: 'SEKAI NO OWARI',
      duration: 213,
      file: TdFileRef(id: 77),
    ),
  );

  MusicPlayerController controller() => MusicPlayerController.shared;

  setUp(() {
    controller()
      ..current = track()
      ..hidden = false
      ..collapsed = false;
  });

  tearDown(() {
    controller()
      ..current = null
      ..queue = const []
      ..hidden = true
      ..collapsed = false;
  });

  Widget pageHost({required VoidCallback onBack, required Widget body}) =>
      MaterialApp(
        home: FullPageBackSwipe(
          enabled: true,
          onBack: onBack,
          child: Scaffold(body: body),
        ),
      );

  testWidgets('the expanded bar owns its rightward drag', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(
      pageHost(
        onBack: () => backs++,
        body: const Align(
          alignment: Alignment.bottomCenter,
          child: GlobalMusicPlayerBar(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(GlobalMusicPlayerBar),
        matching: find.byType(ExcludeFromBackSwipe),
      ),
      findsOneWidget,
    );

    // Past the bar's own 32% minimise threshold (128pt of 400).
    await tester.drag(find.byType(GlobalMusicPlayerBar), const Offset(170, 0));
    // The bar settles its slide, then minimises on a 190 ms timer.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(backs, 0, reason: 'the bar owns horizontal drags');
    expect(
      controller().collapsed,
      isTrue,
      reason: 'the drag must still reach the bar and minimise the player',
    );
  });

  testWidgets('the mini player card owns its rightward drag', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(
      pageHost(
        onBack: () => backs++,
        body: const Center(
          child: SizedBox(width: 320, child: MusicMiniPlayerCard()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MusicMiniPlayerCard),
        matching: find.byType(ExcludeFromBackSwipe),
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(MusicMiniPlayerCard), const Offset(170, 0));
    await tester.pumpAndSettle();

    expect(backs, 0, reason: 'the card owns horizontal drags');
    expect(
      controller().collapsed,
      isTrue,
      reason: 'the drag must still reach the card and collapse it',
    );
  });

  testWidgets('the collapsed overlay pill owns its rightward drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    controller().collapsed = true;
    var backs = 0;
    await tester.pumpWidget(
      pageHost(
        onBack: () => backs++,
        body: const Stack(children: [GlobalMusicPlayerOverlay()]),
      ),
    );
    await tester.pump();

    expect(find.byKey(musicCollapsedOverlayKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlobalMusicPlayerOverlay),
        matching: find.byType(ExcludeFromBackSwipe),
      ),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(musicCollapsedOverlayKey),
      const Offset(170, 0),
    );
    await tester.pumpAndSettle();

    expect(backs, 0, reason: 'the collapsed pill owns horizontal drags');
  });

  testWidgets('a rightward drag beside the player still goes back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(
      pageHost(
        onBack: () => backs++,
        body: const Column(
          children: [
            Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
            GlobalMusicPlayerBar(),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.dragFrom(const Offset(200, 300), const Offset(180, 0));
    await tester.pumpAndSettle();

    expect(backs, 1, reason: 'the full-page swipe stays available elsewhere');
  });
}
