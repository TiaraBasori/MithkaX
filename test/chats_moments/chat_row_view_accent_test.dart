import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/settings/appearance/accent_color_picker_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatSummary _peer({int accent = 0, int profile = -1}) => ChatSummary(
  id: 42,
  title: 'Alice',
  lastMessage: 'hi',
  lastMessageId: 10,
  date: 0,
  unreadCount: 0,
  order: 100,
  isMuted: false,
  kind: ChatKind.privateChat,
  peerUserId: 7,
  peerIsPremium: true,
  peerAccentColorId: accent,
  peerProfileAccentColorId: profile,
);

Future<ThemeController> _pumpRow(WidgetTester tester, ChatSummary chat) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 390, child: ChatRowView(chat: chat)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return theme;
}

Color? _nameColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Alice')).style?.color;

void main() {
  testWidgets('profile colour wins over the name colour', (tester) async {
    // The peer set only 主页颜色 (2), leaving the name colour at 0: the list
    // has to show the profile hue the profile page's cover uses.
    await _pumpRow(tester, _peer(profile: 2));

    expect(_nameColor(tester), kAccentColors[2]);
  });

  testWidgets('without a profile colour the name colour still paints', (
    tester,
  ) async {
    await _pumpRow(tester, _peer());

    expect(_nameColor(tester), kAccentColors[0]);
  });

  testWidgets('a premium profile id past the palette does not throw', (
    tester,
  ) async {
    await _pumpRow(tester, _peer(profile: 9));

    expect(tester.takeException(), isNull);
    // Those hues need updateProfileAccentColors, which the list does not
    // carry; the row falls back to the brand colour instead of indexing out.
    expect(_nameColor(tester), AppTheme.brand);
  });
}
