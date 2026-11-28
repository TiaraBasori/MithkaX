//
//  profile_music_source_test.dart
//
//  The profile page's music row must describe the account's REAL saved track
//  (`userFullInfo.first_profile_audio`). It used to hardcode
//  'SEKAI NO OWARI - The Peak' for our own profile and then regex-scrape a
//  title out of the free-text `music` / bio fields and search the account's
//  audio messages for something that matched — so the row showed a different
//  track from the one Telegram actually has.
//
//  A full widget test of the page needs a TdClient, so this pins the shape of
//  the source instead: the parser is used, and the hardcoded / scraped paths
//  are gone.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() async {
    source = await File('lib/profile/profile_detail_view.dart').readAsString();
  });

  test('the row reads the saved track from first_profile_audio', () {
    expect(source, contains("full.obj('first_profile_audio')"));
    expect(source, contains('TDParse.musicFromAudio'));
  });

  test('no hardcoded track is ever shown', () {
    expect(source, isNot(contains('SEKAI NO OWARI')));
    expect(source, isNot(contains('_defaultOwnMusicTitle')));
  });

  test('the title is not scraped out of bio text or searched for', () {
    expect(source, isNot(contains('_extractMusicTitle')));
    expect(source, isNot(contains('searchMessagesFilterAudio')));
    expect(source, isNot(contains('_resolveMusicCandidate')));
  });

  test('the saved track is played through the shared player', () {
    expect(source, contains('_profileMusicMessage'));
    expect(source, contains('MusicPlayerController.shared'));
  });
}
