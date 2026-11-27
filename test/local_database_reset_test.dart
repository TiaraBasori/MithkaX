//
//  local_database_reset_test.dart
//
//  “重置数据库” wipes the caches the app can rebuild (TDLib media, emoji pack
//  binaries, the kept-message mirror, search history) and touches nothing that
//  makes the install the user's: no preference write, no session close.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/search_history_store.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/settings/downloads_storage/data_storage_service.dart';
import 'package:mithka/settings/downloads_storage/local_database_reset.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';

class _FakeStorage extends DataStorageService {
  _FakeStorage();

  final calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> optimize({
    required int size,
    required int ttl,
    List<Map<String, dynamic>> fileTypes = const [],
    List<int> chatIds = const [],
    List<int> excludeChatIds = const [],
    bool returnDeletedStatistics = false,
    int count = 1000000000,
    int immunityDelay = 3600,
    int chatLimit = 100,
  }) async {
    calls.add({
      'size': size,
      'ttl': ttl,
      'immunityDelay': immunityDelay,
      'types': fileTypes.length,
    });
    return {'@type': 'ok'};
  }
}

class _FakeEmoji extends EmojiFontCatalog {
  _FakeEmoji() : super.forTesting();

  int clears = 0;

  @override
  Future<int> clearCache() async {
    clears += 1;
    return 3;
  }
}

class _FakeSearchHistory extends SearchHistoryStore {
  int clears = 0;

  @override
  Future<void> clearAll() async {
    clears += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the reset evicts caches and never reaches the session', () async {
    final storage = _FakeStorage();
    final emoji = _FakeEmoji();
    final search = _FakeSearchHistory();
    final history = MessageHistoryStore.forTesting();

    await LocalDatabaseReset.run(
      storage: storage,
      emoji: emoji,
      searchHistory: search,
      history: history,
    );

    expect(storage.calls, hasLength(1));
    expect(storage.calls.single['size'], 0);
    expect(storage.calls.single['ttl'], 0);
    expect(
      storage.calls.single['types'],
      0,
      reason: 'an empty file-type list asks TDLib to evict every cached type',
    );
    expect(emoji.clears, 1);
    expect(search.clears, 1);
    expect(history.entries, isEmpty);
  });

  test('the copy names what survives', () {
    expect(LocalDatabaseReset.keepsLabel, contains('session'));
    expect(LocalDatabaseReset.keepsLabel, contains('settings'));
  });
}
