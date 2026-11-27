//
//  local_database_reset.dart
//
//  “重置数据库”: wipe every local cache the app rebuilt from the network,
//  while keeping what makes the install *the user's* — the TDLib session
//  (no re-login), every preference, the chosen emoji pack, drafts, saved
//  messages and retained downloads.
//
//  What goes: the kept-message mirror and its media snapshots, TDLib's cached
//  media files, downloaded emoji font binaries, the recorded search history
//  and Flutter's in-memory image cache.
//
//  TDLib's own database directory is deliberately NOT touched: the account's
//  authorization key lives inside it, so deleting it would log the user out
//  even though the request is only about a stale cache.
//

import 'package:flutter/painting.dart';

import '../../chats/search_history_store.dart';
import '../../history/message_history_store.dart';
import '../../theme/emoji_font_catalog.dart';
import '../downloads_storage/data_storage_service.dart';

class LocalDatabaseReset {
  LocalDatabaseReset._();

  /// Human-readable description of what survives the wipe, for the confirm
  /// card and the settings subtitle. One place so the copy cannot drift.
  static const keepsLabel = 'settings, session, drafts and saved downloads';

  static Future<void> run({
    DataStorageService? storage,
    MessageHistoryStore? history,
    EmojiFontCatalog? emoji,
    SearchHistoryStore? searchHistory,
  }) async {
    // 1. The kept-message mirror plus every media snapshot it wrote.
    (history ?? MessageHistoryStore.shared).clearAll();

    // 2. TDLib's cached media. `optimizeStorage` with size 0 and an empty
    //    type list asks it to drop every cached file it may evict; the
    //    session, the message database and the chat list are untouched.
    try {
      await (storage ?? const DataStorageService()).optimize(
        size: 0,
        ttl: 0,
        immunityDelay: 0,
        chatLimit: 200,
      );
    } catch (_) {
      // A slot without an active client (signed out, or a preview surface)
      // has nothing to evict; the rest of the reset still stands.
    }

    // 3. Downloaded emoji packs: binaries only, the catalog manifest and the
    //    chosen key stay so the next launch re-fetches what is needed.
    try {
      await (emoji ?? EmojiFontCatalog.shared).clearCache();
    } catch (_) {
      // Cache accounting is best effort.
    }

    // 4. Search history is a convenience cache, not a preference.
    try {
      await (searchHistory ?? SearchHistoryStore.shared).clearAll();
    } catch (_) {
      // Same.
    }

    // 5. Decoded images held by this process.
    final images = PaintingBinding.instance.imageCache;
    images.clear();
    images.clearLiveImages();
  }
}
