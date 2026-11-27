//
//  local_database_reset.dart
//
//  “重置数据库”: drop the local message databases and rebuild them from the
//  server, while keeping what makes the install *the user's* — the session (no
//  re-login), every preference, the chosen emoji pack, drafts on bot accounts
//  and their on-device histories.
//
//  What goes: every live Telegram account's TDLib database and media cache
//  (re-created from the session string, so the account stays signed in), the
//  kept-message mirror and its media snapshots, downloaded emoji binaries,
//  unsent drafts, saved downloads, the recorded search history and Flutter's
//  in-memory image cache.
//
//  Bot-API accounts are deliberately NOT wiped: their on-device history is the
//  only copy of what the bot sent, not a cache of a server database.
//

import 'package:flutter/painting.dart';

import '../../chats/search_history_store.dart';
import '../../history/message_history_store.dart';
import '../../tdlib/td_client.dart';
import '../../theme/emoji_font_catalog.dart';
import 'data_storage_service.dart';
import 'retained_download_store.dart';

/// What a reset managed to do. [failures] is empty on a clean run; any entry
/// means that account's database (and only that account) was left as it was.
class LocalDatabaseResetResult {
  const LocalDatabaseResetResult({
    required this.databasesReset,
    required this.failures,
  });

  final int databasesReset;
  final List<String> failures;

  bool get ok => failures.isEmpty;
}

class LocalDatabaseReset {
  LocalDatabaseReset._();

  /// Human-readable description of what survives the wipe, for the confirm
  /// card and the settings subtitle. One place so the copy cannot drift.
  static const keepsLabel = 'settings, session and the chosen emoji pack';

  /// The retained-download stores of every live slot, so a multi-account
  /// install is cleaned in full rather than for the active account only.
  static Future<List<RetainedDownloadStore>> _downloadStores(
    TdClient client,
  ) async {
    final stores = <RetainedDownloadStore>[];
    final slots = {
      ...client.configuredSlots,
      if (client.hasActiveClient) client.activeSlot,
    };
    for (final slot in slots) {
      try {
        stores.add(await RetainedDownloadStore.forAccount(slot));
      } catch (_) {
        // A slot without a directory has nothing saved.
      }
    }
    return stores;
  }

  static Future<LocalDatabaseResetResult> run({
    TdClient? client,
    DataStorageService? storage,
    MessageHistoryStore? history,
    EmojiFontCatalog? emoji,
    SearchHistoryStore? searchHistory,
    List<RetainedDownloadStore>? downloads,
  }) async {
    final td = client ?? TdClient.shared;
    final failures = <String>[];

    // 1. The kept-message mirror plus every media snapshot it wrote. Flushed
    //    here: a debounced persist would let a kill right after the tap
    //    resurrect the old entries.
    try {
      await (history ?? MessageHistoryStore.shared).clearAllAndFlush();
    } catch (error) {
      failures.add('kept messages: $error');
    }

    // 2. Every live Telegram account's database and media cache. TDLib has no
    //    API to drop the database in place, so each slot is reopened from its
    //    own exported session string (see TdClient.resetSlotDatabase).
    var databasesReset = 0;
    try {
      databasesReset = await td.resetLocalDatabases();
    } catch (error) {
      failures.add('message database: $error');
    }

    // 3. If the database path could not run (an account that cannot export a
    //    session), still evict what TDLib may drop on its own. This is the old
    //    cache-only behaviour, not a substitute for the reset.
    if (databasesReset == 0) {
      try {
        await (storage ?? const DataStorageService()).optimize(
          size: 0,
          ttl: 0,
          immunityDelay: 0,
          chatLimit: 200,
        );
      } catch (_) {
        // A slot without an active client has nothing to evict.
      }
    }

    // 4. Downloaded emoji packs: binaries only, the catalog manifest and the
    //    chosen key stay so the next launch re-fetches what is needed.
    try {
      await (emoji ?? EmojiFontCatalog.shared).clearCache();
    } catch (_) {
      // Cache accounting is best effort.
    }

    // 5. Saved downloads: the retained copies the user asked to keep. Each
    //    entry owns a file plus its metadata, and removing one is exactly the
    //    panel's own delete path.
    try {
      final stores = downloads ?? await _downloadStores(td);
      for (final store in stores) {
        for (final entry in await store.list()) {
          await store.remove(entry.id).catchError((_) {});
        }
      }
    } catch (_) {
      // A signed-out slot has no store.
    }

    // 6. Search history is a convenience cache, not a preference.
    try {
      await (searchHistory ?? SearchHistoryStore.shared).clearAll();
    } catch (_) {
      // Same.
    }

    // 7. Decoded images held by this process. Their files are gone with the
    //    database and media cache, so the cache must not paint them again.
    final images = PaintingBinding.instance.imageCache;
    images.clear();
    images.clearLiveImages();

    return LocalDatabaseResetResult(
      databasesReset: databasesReset,
      failures: List.unmodifiable(failures),
    );
  }
}
