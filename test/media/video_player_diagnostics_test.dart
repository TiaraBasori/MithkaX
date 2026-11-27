//
//  video_player_diagnostics_test.dart
//
//  A player whose chrome never appears on a phone cannot be debugged from a
//  desktop: there is no logcat. Three fingers held on the surface copy a
//  snapshot of what the player believes, so the report can be pasted back.
//

import 'dart:async';
import 'dart:io';

import 'package:cineplay/cineplay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FakeVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  var _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    _events[playerId] = StreamController<VideoEvent>.broadcast();
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // dispose() owns and closes this controller.
    // ignore: close_sinks
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(minutes: 2),
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

Future<void> _pumpUntilPlayerReady(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (
    var attempt = 0;
    attempt < 40 && find.byType(FVideoPlayer).evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three fingers copy a player report', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlatform();
    try {
      SharedPreferences.setMockInitialValues(const {});
      final path = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: 930, localPath: path),
            width: 1920,
            height: 1080,
            streamQuery: (request) async {
              final length = await File(path).length();
              return <String, dynamic>{
                '@type': 'file',
                'id': 930,
                'size': length,
                'expected_size': length,
                'local': {
                  '@type': 'localFile',
                  'path': path,
                  'download_offset': 0,
                  'downloaded_prefix_size': length,
                  'downloaded_size': length,
                  'is_downloading_active': false,
                  'is_downloading_completed': true,
                },
              };
            },
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      final center = tester.getCenter(find.byType(FVideoPlayer));
      final fingers = <TestGesture>[];
      for (var pointer = 1; pointer <= 3; pointer++) {
        fingers.add(
          await tester.startGesture(
            center + Offset(pointer * 12.0, 0),
            pointer: pointer,
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      for (final finger in fingers) {
        await finger.up();
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(copied, hasLength(1));
      expect(copied.single, contains('mithkax video player'));
      expect(copied.single, contains('chrome builds:'));
      expect(copied.single, contains('presentation: fullscreen'));
      expect(
        find.byKey(const ValueKey('video-player-diagnostics-copied')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 11));
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
    }
  });
}
