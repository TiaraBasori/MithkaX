import 'dart:io';

import 'package:flutter/services.dart';

/// Ends the app's process when the state on screen must not survive the action
/// that just ran.
///
/// A local database reset deletes the store every page in memory was built
/// from; repainting the settings screen over that would leave the account
/// looking signed out until the next launch (the TDLib client under it was
/// closed and reopened). The caller ends the process instead, and the next
/// launch rebuilds from the fresh database.
///
/// Android answers through the app-icon channel's `quit` (retire the task,
/// then kill the process). Desktop ends the Dart process. iOS has no supported
/// way for an app to terminate itself, so it reports that the app is still
/// running and the caller keeps its recovered state.
const MethodChannel _appIconChannel = MethodChannel('mithka/app_icon');

/// Whether the caller should assume this process is going away.
Future<bool> quitAppProcess() async {
  if (Platform.isIOS) return false;
  if (Platform.isAndroid) {
    try {
      await _appIconChannel.invokeMethod<void>('quit');
      return true;
    } catch (_) {
      // A build without the bridge (or a dying process) keeps running.
      return false;
    }
  }
  exit(0);
}
