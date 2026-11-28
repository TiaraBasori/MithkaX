//
//  chat_folder_tab_drag_scroll_test.dart
//
//  The reference client's folder tabs follow a folder swipe: while the list
//  travels toward the neighbour, its tab strip scrolls that neighbour's tab
//  into view (`FilterTabsView.selectTabWithId(id, progress)` →
//  `scrollToChild(position)`). MithkaX used a lazy horizontal ListView, so a
//  tab that was entirely outside the viewport had no render object and the
//  strip never moved — the reported "目标文件夹整个在屏幕外的时候没反应".
//
//  The strip lays every tab out in a row and drives its own offset from the
//  folder drag's progress. These cases pin both halves: a mid-drag offset
//  move and every landed tab ending fully visible, including the last one
//  which starts off-screen.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _chat(
  int id, {
  String list = 'chatListMain',
  int order = 100,
}) => {
  '@type': 'chat',
  'id': id,
  'title': 'Chat $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': 1000 + id},
  'last_message': {
    '@type': 'message',
    'id': id * 10,
    'chat_id': id,
    'date': order,
    'is_outgoing': false,
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'hi', 'entities': <Object>[]},
    },
  },
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': list},
      'order': order,
      'is_pinned': false,
    },
  ],
};

Future<void> _pumpChatList(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'communitiesEnabled': false,
    'showChatListSearch': true,
    'chatListSwipeMode.v1': 'switchFolders',
  });
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: const Scaffold(body: ChatListView()),
      ),
    ),
  );

  updates.add({
    '@type': 'updateConnectionState',
    'state': {'@type': 'connectionStateReady'},
  });
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      for (var i = 1; i <= 7; i++)
        {
          'id': i,
          'title': 'Folder $i',
          'pinned_chat_ids': <int>[],
          'included_chat_ids': [200 + i],
        },
    ],
  });
  for (var i = 1; i <= 30; i++) {
    updates.add({
      '@type': 'updateNewChat',
      'chat': _chat(1000 - i, order: 1000 - i),
    });
  }
  for (var i = 1; i <= 7; i++) {
    updates.add({
      '@type': 'updateNewChat',
      'chat': {..._chat(200 + i), 'title': 'Folder chat $i'},
    });
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

ScrollableState _tabStripScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-folder-tabs')),
        matching: find.byType(Scrollable),
      ),
    );

/// Swipes the chat list one folder forward (travel to the left). The anchor
/// is a fixed point in the list area: each folder has its own chats, so a
/// chat name from another folder is not a usable finder.
Future<void> _swipeToNextFolder(WidgetTester tester) async {
  final stripBottom = tester
      .getBottomLeft(find.byKey(const ValueKey('chat-folder-tabs')))
      .dy;
  final gesture = await tester.startGesture(Offset(340, stripBottom + 80));
  await tester.pump(const Duration(milliseconds: 40));
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(const Offset(-26, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
          'getConnectionState' => {'@type': 'connectionStateReady'},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'the strip travels with the drag and lands every off-screen tab',
    (tester) async {
      await _pumpChatList(tester, updates);
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('chat-folder-tabs')),
      );
      final scrollable = _tabStripScrollable(tester);
      expect(scrollable.position.pixels, 0);

      // The seventh folder starts entirely outside the 390dp strip.
      final lastTab = tester.getRect(find.text('Folder 7'));
      expect(
        lastTab.left,
        greaterThan(stripRect.right),
        reason: 'the fixture must put the target tab off-screen',
      );

      for (var step = 1; step <= 7; step++) {
        final before = scrollable.position.pixels;
        final targetBefore = tester.getRect(find.text('Folder $step'));
        final needsScroll = targetBefore.right > stripRect.right + 0.5;
        final stripBottom = tester
            .getBottomLeft(find.byKey(const ValueKey('chat-folder-tabs')))
            .dy;
        final gesture = await tester.startGesture(
          Offset(340, stripBottom + 80),
        );
        await tester.pump(const Duration(milliseconds: 40));
        for (var i = 0; i < 8; i++) {
          await gesture.moveBy(const Offset(-26, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        // While the finger is still down the strip has already moved toward the
        // incoming folder — the reference's selectTabWithId(progress). A target
        // that is already wholly visible needs no travel.
        if (needsScroll) {
          expect(
            scrollable.position.pixels,
            greaterThan(before),
            reason: 'the strip follows the folder drag, step $step',
          );
        } else {
          expect(
            scrollable.position.pixels,
            closeTo(before, 0.5),
            reason:
                'an already visible target must not jerk the strip, step $step',
          );
        }
        await gesture.up();
        await tester.pumpAndSettle();

        final tab = tester.getRect(find.text('Folder $step'));
        expect(
          tab.left,
          greaterThanOrEqualTo(stripRect.left - 0.5),
          reason: 'landed tab $step is inside the strip',
        );
        expect(
          tab.right,
          lessThanOrEqualTo(stripRect.right + 0.5),
          reason: 'landed tab $step is fully visible',
        );
      }

      expect(
        scrollable.position.pixels,
        greaterThan(0),
        reason: 'reaching the last folder had to scroll the strip',
      );
      await _dispose(tester);
    },
  );

  testWidgets(
    'selecting an off-screen folder from the pager scrolls the strip',
    (tester) async {
      await _pumpChatList(tester, updates);
      final scrollable = _tabStripScrollable(tester);
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('chat-folder-tabs')),
      );
      expect(scrollable.position.pixels, 0);

      // Seven commits land on the last folder; the strip has to have followed.
      for (var step = 1; step <= 7; step++) {
        await _swipeToNextFolder(tester);
      }
      final last = tester.getRect(find.text('Folder 7'));
      expect(last.right, lessThanOrEqualTo(stripRect.right + 0.5));
      expect(last.left, greaterThanOrEqualTo(stripRect.left - 0.5));
      await _dispose(tester);
    },
  );
}
