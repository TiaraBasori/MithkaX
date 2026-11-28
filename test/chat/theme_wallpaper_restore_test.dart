//
//  theme_wallpaper_restore_test.dart
//
//  Returning to an official theme (a theme with no wallpaper of its own) must
//  put back the background that was in force before a theme shipped its own.
//  The record survives only while that theme background is still what the
//  account shows: a wallpaper the reader picked afterwards wins.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/appearance/chat_wallpaper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late int nextId;

  Map<String, dynamic> fillBackground(int id, int color) => {
    '@type': 'background',
    'id': id,
    'is_dark': false,
    'is_default': false,
    'type': {
      '@type': 'backgroundTypeFill',
      'fill': {'@type': 'backgroundFillSolid', 'color': color},
    },
  };

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getCurrentState':
        return {
          '@type': 'ok',
          'updates': [
            {
              '@type': 'updateDefaultBackground',
              'for_dark_theme': false,
              'background': fillBackground(10, 0x010203),
            },
          ],
        };
      case 'setDefaultBackground':
        final type = request['type'] as Map<String, dynamic>;
        return {
          '@type': 'background',
          'id': nextId++,
          'is_dark': request['for_dark_theme'] == true,
          'is_default': false,
          'type': type,
        };
      case 'deleteDefaultBackground':
        return {'@type': 'ok'};
    }
    return {'@type': 'ok'};
  }

  ChatWallpaperController controller() => ChatWallpaperController(
    preferences: () async => prefs,
    supportDirectory: () async => Directory.systemTemp,
    activeSlot: () => 1,
    hasActiveClient: () => true,
    query: query,
    listenForUpdates: false,
  );

  ChatWallpaper themedWallpaper(int color) => ChatWallpaper.telegram(
    backgroundId: 0,
    remoteType: 'fill',
    colors: [color],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    nextId = 100;
  });

  test('an official theme puts the pre-theme wallpaper back', () async {
    final wallpapers = controller();
    await wallpapers.loadDefaultWallpaper(dark: false, refresh: true);
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x010203]);

    await wallpapers.applyThemeWallpaper(
      themedWallpaper(0x223344),
      dark: false,
    );
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x223344]);

    expect(await wallpapers.restoreThemeWallpaper(dark: false), isTrue);
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x010203]);
    // One restore only: the record is spent.
    expect(await wallpapers.restoreThemeWallpaper(dark: false), isFalse);
  });

  test('theme A -> theme B still returns to the reader wallpaper', () async {
    final wallpapers = controller();
    await wallpapers.loadDefaultWallpaper(dark: false, refresh: true);

    await wallpapers.applyThemeWallpaper(
      themedWallpaper(0x223344),
      dark: false,
    );
    await wallpapers.applyThemeWallpaper(
      themedWallpaper(0x445566),
      dark: false,
    );
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x445566]);

    expect(await wallpapers.restoreThemeWallpaper(dark: false), isTrue);
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x010203]);
  });

  test('a wallpaper picked after the theme wins over the old one', () async {
    final wallpapers = controller();
    await wallpapers.loadDefaultWallpaper(dark: false, refresh: true);
    await wallpapers.applyThemeWallpaper(
      themedWallpaper(0x223344),
      dark: false,
    );

    // A manual pick drops the theme record, even before any restore runs.
    await wallpapers.applyDefaultWallpaper(
      themedWallpaper(0x778899),
      dark: false,
    );
    expect(await wallpapers.restoreThemeWallpaper(dark: false), isFalse);
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x778899]);
  });

  test('with nothing remembered a restore is a no-op', () async {
    final wallpapers = controller();
    await wallpapers.loadDefaultWallpaper(dark: false, refresh: true);
    expect(await wallpapers.restoreThemeWallpaper(dark: false), isFalse);
    expect(wallpapers.defaultWallpaper(dark: false)!.colors, [0x010203]);
  });
}
