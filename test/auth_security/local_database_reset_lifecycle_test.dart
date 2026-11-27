//
//  local_database_reset_lifecycle_test.dart
//
//  “重置数据库” must actually drop the local TDLib database while keeping the
//  account signed in. TDLib has no API for that (the authorization key lives in
//  the same database), so the client exports the slot's session string,
//  materializes it into a staging binlog, swaps the directories while the
//  client is closed and reopens. These cases pin that lifecycle — including the
//  rollback that puts the old database back when the reopened client cannot
//  reach the account — with synthetic credentials, no TDLib binary.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_session_string.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _syntheticAuthKey(int seed) {
  final key = Uint8List(TdSessionString.authKeyLength);
  for (var i = 0; i < key.length; i++) {
    key[i] = ((seed + i * 7) % 251) + 1;
  }
  return key;
}

String _syntheticSession({int userId = 777, int apiId = 2496}) =>
    TdSessionString.encode(
      TdSessionStringData(
        dcId: 2,
        apiId: apiId,
        testMode: false,
        authKey: _syntheticAuthKey(1),
        userId: userId,
        isBot: false,
      ),
    );

Map<String, dynamic> _ready() => const {'@type': 'authorizationStateReady'};
Map<String, dynamic> _waitParameters() => const {
  '@type': 'authorizationStateWaitTdlibParameters',
};
Map<String, dynamic> _me(int userId) => {
  '@type': 'user',
  'id': userId,
  'first_name': 'Synthetic',
};

class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  final List<(int, Map<String, dynamic>)> sent = [];
  final List<(String, String)> imported = [];
  int _nextClientId = 100;

  List<Map<String, dynamic>> sentTo(int clientId, String type) => [
    for (final (id, request) in sent)
      if (id == clientId && request['@type'] == type) request,
  ];

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    sent.add((clientId, decoded));
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    imported.add((sessionString, destinationPath));
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1, 2, 3]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => _syntheticSession(userId: userId, apiId: apiId);

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

class _Harness {
  _Harness(this.client, this.bindings, this.supportDir);

  final TdClient client;
  final _FakeBindings bindings;
  final Directory supportDir;

  Directory slotDir(int slot) =>
      Directory('${supportDir.path}/tdlib/account-$slot');
}

typedef _Respond =
    FutureOr<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

Future<_Harness> _prepare({required _Respond respond}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({
    'mithka.api_credentials.enabled': true,
    'mithka.api_credentials.api_id': '2496',
    'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
  });
  final prefs = await SharedPreferences.getInstance();
  final supportDir = Directory.systemTemp.createTempSync('mithka_reset');
  addTearDown(() {
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });
  final client = TdClient.forTesting();
  final bindings = _FakeBindings(client);
  client.prepareForTesting(
    prefs: prefs,
    supportDir: supportDir.path,
    bindings: bindings,
    queryOverride: (request, clientId) async => respond(request, clientId),
  );
  return _Harness(client, bindings, supportDir);
}

/// Every client reports WaitTdlibParameters once, then Ready, and answers
/// [userId] from getMe (the reopened client can name another account).
_Respond _steadyResponder(int userId, {int? reopenedUserId}) {
  final seen = <int>{};
  return (request, clientId) {
    switch (request['@type']) {
      case 'getAuthorizationState':
        return seen.add(clientId) ? _waitParameters() : _ready();
      case 'getMe':
        return _me(clientId >= 101 ? reopenedUserId ?? userId : userId);
      default:
        return const {'@type': 'ok'};
    }
  };
}

void main() {
  test('a reset swaps in a session-bearing database and reopens it', () async {
    final harness = await _prepare(respond: _steadyResponder(777));
    final slot = await harness.client.restoreSessionSlot(_syntheticSession());
    expect(slot, 1);
    // A marker proves the old database really is replaced, not reused.
    File('${harness.slotDir(1).path}/old-db.marker').writeAsStringSync('old');

    await harness.client.resetSlotDatabase(1);

    // Two imports: the original restore and the reset's staging binlog.
    expect(harness.bindings.imported, hasLength(2));
    expect(
      harness.bindings.imported.last.$2,
      endsWith('account-1.reset/td.binlog'),
    );
    // The old client was closed before the swap and a new one opened the
    // fresh database.
    expect(harness.bindings.sentTo(100, 'close'), hasLength(1));
    expect(harness.client.clientId(1), 101);
    final parameters = harness.bindings.sentTo(101, 'setTdlibParameters');
    expect(parameters, hasLength(1));
    expect(parameters.single['database_directory'], harness.slotDir(1).path);
    // The old database (and its media cache) are gone; the slot still exists.
    expect(
      File('${harness.slotDir(1).path}/old-db.marker').existsSync(),
      isFalse,
    );
    expect(File('${harness.slotDir(1).path}/td.binlog').existsSync(), isTrue);
    expect(harness.client.activeSlot, 1);
  });

  test('a reset that cannot reopen restores the previous database', () async {
    final harness = await _prepare(
      respond: _steadyResponder(777, reopenedUserId: 999),
    );
    await harness.client.restoreSessionSlot(_syntheticSession());
    File('${harness.slotDir(1).path}/old-db.marker').writeAsStringSync('old');

    await expectLater(
      harness.client.resetSlotDatabase(1),
      throwsA(
        isA<TdSessionRestoreException>().having(
          (error) => error.toString(),
          'toString',
          contains('user mismatch'),
        ),
      ),
    );

    // The old database is back in place and a client reopened it.
    expect(
      File('${harness.slotDir(1).path}/old-db.marker').existsSync(),
      isTrue,
    );
    expect(harness.client.clientId(1), isNotNull);
    expect(
      harness.bindings.sentTo(harness.client.clientId(1)!, 'close'),
      isEmpty,
    );
  });

  test('bot-API slots keep their on-device history', () async {
    final harness = await _prepare(respond: _steadyResponder(777));
    await harness.client.restoreSessionSlot(_syntheticSession());
    final reset = await harness.client.resetLocalDatabases();
    expect(reset, 1);
    expect(harness.bindings.sentTo(100, 'close'), hasLength(1));
  });
}
