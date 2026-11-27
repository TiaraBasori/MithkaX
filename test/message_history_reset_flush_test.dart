//
//  message_history_reset_flush_test.dart
//
//  “重置数据库” must be finished when it returns. clearAll() alone only
//  schedules the mirror rewrite 800 ms later and the media snapshotter does
//  nothing while its directory is still unresolved (a fresh process, where
//  only ensureDirResolved sets it). Killing the app right after the tap used to
//  resurrect the whole mirror and leave every attachment on disk;
//  clearAllAndFlush removes both, synchronously.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';

/// Records the order the flush walks the snapshotter in: resolution must come
/// before deletion, or a fresh process deletes nothing.
class _RecordingSnapshotter extends MessageMediaSnapshotter {
  _RecordingSnapshotter() : super.forTesting();

  final List<String> calls = [];

  @override
  Future<void> ensureDirResolved() async {
    calls.add('resolve');
  }

  @override
  void deleteAll() {
    calls.add('delete');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearAllAndFlush removes the mirror file at once', () async {
    final dir = Directory.systemTemp.createTempSync('mirror-flush');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(
      '${dir.path}/message-history.json',
    ).writeAsStringSync(jsonEncode({'version': 2, 'entries': const []}));
    final store = MessageHistoryStore.forTesting()
      ..fileDir = dir
      ..mediaSnapshotter = _RecordingSnapshotter();
    await store.ensureLoaded();

    await store.clearAllAndFlush();

    expect(
      File('${dir.path}/message-history.json').existsSync(),
      isFalse,
      reason: 'an empty mirror is no file, and the write must not be deferred',
    );
    expect(File('${dir.path}/message-history.json.tmp').existsSync(), isFalse);
  });

  test(
    'the snapshot directory is resolved before anything is deleted',
    () async {
      final dir = Directory.systemTemp.createTempSync('mirror-flush-order');
      addTearDown(() => dir.deleteSync(recursive: true));
      final snapshotter = _RecordingSnapshotter();
      final store = MessageHistoryStore.forTesting()
        ..fileDir = dir
        ..mediaSnapshotter = snapshotter;

      await store.clearAllAndFlush();

      // clearAll() deletes in memory first; the flush must resolve the
      // directory and delete AGAIN, because the first pass ran before the
      // directory existed in a fresh process.
      expect(snapshotter.calls.length, greaterThanOrEqualTo(2));
      expect(
        snapshotter.calls.sublist(snapshotter.calls.length - 2),
        ['resolve', 'delete'],
        reason:
            'a fresh process has no snapshot directory yet; deleteAll() without '
            'resolving it leaves every attachment behind',
      );
    },
  );

  test('attachments go when the snapshot directory is known', () async {
    final dir = Directory.systemTemp.createTempSync('mirror-flush-media');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mediaDir = Directory('${dir.path}/message-history-media')
      ..createSync(recursive: true);
    final snapshot = File('${mediaDir.path}/1_2_3_m.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final store = MessageHistoryStore.forTesting()
      ..fileDir = dir
      ..mediaSnapshotter = (MessageMediaSnapshotter.forTesting()
        ..dir = mediaDir);

    await store.clearAllAndFlush();

    expect(snapshot.existsSync(), isFalse);
  });
}
