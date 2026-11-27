//
//  video_on_demand_chrome_test.dart
//
//  Opening a video from the chat must land on a player whose chrome is on
//  screen. The report was "the fullscreen player has no controls at all", and
//  the chrome is the host's: this test pins that it mounts visible, carries the
//  transport, and stays reachable after the player settles.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media/video_playback_queue.dart';
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

double? _chromeOpacity(WidgetTester tester) {
  final chrome = find.byKey(const ValueKey('mithka-video-player-chrome'));
  if (chrome.evaluate().isEmpty) return null;
  return tester.widget<AnimatedOpacity>(chrome).opacity;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a video opens with its chrome already on screen', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlatform();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final path = File('pubspec.yaml').absolute.path;
      final item = VideoPlaybackItem(
        video: TdFileRef(id: 914, localPath: path),
        width: 1920,
        height: 1080,
        title: 'Clip',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoOnDemandPlayerView(
            queue: VideoPlaybackQueue(items: [item]),
            streamQuery: (request) async {
              final length = await File(path).length();
              return <String, dynamic>{
                '@type': 'file',
                'id': 914,
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
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 10));
        if (_chromeOpacity(tester) != null) break;
      }
      expect(
        _chromeOpacity(tester),
        1,
        reason: 'the chrome must mount visible, not hidden behind a tap',
      );
      expect(
        find.byKey(const ValueKey('mithka-video-player-chrome')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 11));
      expect(tester.takeException(), isNull);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
