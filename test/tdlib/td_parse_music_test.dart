//
//  td_parse_music_test.dart
//
//  `userFullInfo.first_profile_audio` is the real profile track: the same
//  `audio` object a messageAudio carries, without a message around it.
//  TDParse.musicFromAudio is the one parser for both, so the profile page and
//  the transcript cannot disagree about title, performer, cover or duration.
//

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

Map<String, dynamic> _file(int id, {int size = 4096}) => {
  '@type': 'file',
  'id': id,
  'size': size,
  'expected_size': size,
  'local': {
    '@type': 'localFile',
    'path': '',
    'download_offset': 0,
    'downloaded_prefix_size': 0,
    'downloaded_size': 0,
    'is_downloading_active': false,
    'is_downloading_completed': false,
  },
};

Map<String, dynamic> _audio({
  String? title = 'The Peak',
  String? performer = 'SEKAI NO OWARI',
  String? fileName = 'the-peak.mp3',
}) => {
  '@type': 'audio',
  'duration': 213,
  'title': title,
  'performer': performer,
  'file_name': fileName,
  'album_cover_minithumbnail': {
    '@type': 'minithumbnail',
    'width': 40,
    'height': 40,
    'data': base64Encode(const [1, 2, 3, 4]),
  },
  'album_cover_thumbnail': {
    '@type': 'thumbnail',
    'format': {'@type': 'thumbnailFormatJpeg'},
    'width': 320,
    'height': 320,
    'file': _file(42),
  },
  'audio': _file(41, size: 8192),
};

void main() {
  test('musicFromAudio reads the saved track document', () {
    final music = TDParse.musicFromAudio(_audio());
    expect(music, isNotNull);
    expect(music!.title, 'The Peak');
    expect(music.performer, 'SEKAI NO OWARI');
    expect(music.duration, 213);
    expect(music.file?.id, 41);
    expect(music.file?.size, 8192);
    expect(music.cover?.id, 42);
    expect(music.cover?.miniThumb, isNotNull);
  });

  test('a missing title falls back to the file name', () {
    final music = TDParse.musicFromAudio(_audio(title: null));
    expect(music?.title, 'the-peak.mp3');
  });

  test('a blank title falls back to the file name, not an empty row', () {
    final music = TDParse.musicFromAudio(_audio(title: '   '));
    expect(music?.title, 'the-peak.mp3');
  });

  test('a track with no metadata falls back to the Music label', () {
    final music = TDParse.musicFromAudio(_audio(title: null, fileName: null));
    expect(music?.title, AppStrings.t(AppStringKeys.profileDetailMusic));
  });

  test('no audio document means no track', () {
    expect(TDParse.musicFromAudio(null), isNull);
  });

  test('messageAudio parses to the same track', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 5,
      'chat_id': 9,
      'date': 1700000000,
      'is_outgoing': false,
      'content': {'@type': 'messageAudio', 'audio': _audio()},
    });
    expect(message?.music?.title, 'The Peak');
    expect(message?.music?.performer, 'SEKAI NO OWARI');
    expect(message?.music?.duration, 213);
    expect(message?.music?.file?.id, 41);
    expect(message?.music?.cover?.id, 42);
  });
}
