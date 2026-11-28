//
//  reaction_recent_reactors_test.dart
//
//  TDLib 1.8.69 names the last senders per bucket in
//  `reactionCount.recent_sender_ids` (at most three). The reference client uses
//  them for the avatar chips, so the parser has to keep each bucket's own
//  senders — a flat list would show a 👍 reactor under 🔥. The older
//  `messageReactions.recent_reactions` shape stays readable for old fixtures,
//  and `can_get_added_reactions` decides whether a list can be opened at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

Map<String, dynamic> _peer(int userId) => {
  '@type': 'messageSenderUser',
  'user_id': userId,
};

Map<String, dynamic> _chatPeer(int chatId) => {
  '@type': 'messageSenderChat',
  'chat_id': chatId,
};

Map<String, dynamic> _reactionCount(
  String emoji,
  int count, {
  bool chosen = false,
  List<Map<String, dynamic>>? recentSenderIds,
}) => {
  '@type': 'reactionCount',
  'type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
  'total_count': count,
  'is_chosen': chosen,
  'recent_sender_ids': ?recentSenderIds,
};

Map<String, dynamic> _recent(String emoji, int userId) => {
  '@type': 'messagePeerReaction',
  'peer_id': _peer(userId),
  'date': 1700000000,
  'reaction': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
};

Map<String, dynamic> _message(
  Map<String, dynamic> reactions, {
  bool? canGetAddedReactions = true,
}) => {
  '@type': 'message',
  'id': 1,
  'chat_id': -100123,
  'date': 1700000000,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'hi'},
  },
  'interaction_info': {
    '@type': 'messageInteractionInfo',
    'reactions': {
      '@type': 'messageReactions',
      'can_get_added_reactions': ?canGetAddedReactions,
      ...reactions,
    },
  },
};

void main() {
  test('each bucket keeps its own recent_sender_ids', () {
    final message = {
      '@type': 'message',
      'id': 1,
      'chat_id': -100123,
      'date': 1700000000,
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'reactions': {
          '@type': 'messageReactions',
          'total_count': 3,
          'reactions': [
            _reactionCount(
              '👍',
              2,
              chosen: true,
              recentSenderIds: [_peer(10), _peer(12)],
            ),
            _reactionCount('🔥', 1, recentSenderIds: [_chatPeer(-100999)]),
          ],
        },
      },
    };

    final reactions = TDParse.reactionsFrom(message);
    expect(reactions, hasLength(2));
    expect(reactions[0].emoji, '👍');
    expect(reactions[0].count, 2);
    expect(reactions[0].chosen, isTrue);
    expect(
      reactions[0].reactors.map((r) => r.senderId).toList(),
      [10, 12],
      reason: 'the 👍 bucket lists its own senders, in TDLib order',
    );
    expect(reactions[1].emoji, '🔥');
    expect(
      reactions[1].reactors.map((r) => r.senderId).toList(),
      [-100999],
      reason: 'a chat sender keeps its negative chat id',
    );
  });

  test('a zero sender id is skipped', () {
    final reactions = TDParse.reactionsFrom(
      _message({
        'reactions': [
          _reactionCount('👍', 1, recentSenderIds: [_peer(0), _peer(10)]),
        ],
      }),
    );

    expect(reactions.single.reactors.map((r) => r.senderId), [10]);
  });

  test('the legacy recent_reactions shape still parses', () {
    final message = {
      '@type': 'message',
      'id': 1,
      'chat_id': -100123,
      'date': 1700000000,
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'reactions': {
          '@type': 'messageReactions',
          'total_count': 3,
          'reactions': [_reactionCount('👍', 2), _reactionCount('🔥', 1)],
          'recent_reactions': [
            _recent('👍', 10),
            _recent('🔥', 11),
            _recent('👍', 12),
          ],
        },
      },
    };

    final reactions = TDParse.reactionsFrom(message);
    expect(
      reactions[0].reactors.map((r) => r.senderId).toList(),
      [10, 12],
      reason: 'the old per-message list is filtered per bucket',
    );
    expect(reactions[1].reactors.map((r) => r.senderId).toList(), [11]);
    expect(reactions[0].reactors.first.date, 1700000000);
  });

  test('recent_sender_ids wins over a stale recent_reactions list', () {
    final reactions = TDParse.reactionsFrom({
      '@type': 'message',
      'id': 1,
      'chat_id': -100123,
      'date': 1700000000,
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'reactions': {
          '@type': 'messageReactions',
          'reactions': [
            _reactionCount('👍', 2, recentSenderIds: [_peer(20)]),
          ],
          'recent_reactions': [_recent('👍', 10)],
        },
      },
    });

    expect(reactions.single.reactors.map((r) => r.senderId), [20]);
  });

  test('a custom-emoji bucket matches by document id', () {
    final message = {
      '@type': 'message',
      'id': 1,
      'chat_id': -100123,
      'date': 1700000000,
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'reactions': {
          '@type': 'messageReactions',
          'total_count': 1,
          'reactions': [
            {
              '@type': 'reactionCount',
              'type': {
                '@type': 'reactionTypeCustomEmoji',
                'custom_emoji_id': '5372981976804366741',
              },
              'total_count': 1,
              'is_chosen': false,
            },
          ],
          'recent_reactions': [
            {
              '@type': 'messagePeerReaction',
              'peer_id': {'@type': 'messageSenderChat', 'chat_id': -100999},
              'date': 1700000000,
              'reaction': {
                '@type': 'reactionTypeCustomEmoji',
                'custom_emoji_id': '5372981976804366741',
              },
            },
          ],
        },
      },
    };

    final reactions = TDParse.reactionsFrom(message);
    expect(reactions, hasLength(1));
    expect(reactions.single.customEmojiId, 5372981976804366741);
    expect(reactions.single.reactors.single.senderId, -100999);
  });

  test('can_get_added_reactions false hides the reactor list', () {
    final hidden = _message({}, canGetAddedReactions: false);
    expect(TDParse.reactionsCanSeeListFrom(hidden), isFalse);
    expect(TDParse.message(hidden)!.reactionsCanSeeList, isFalse);

    final shown = _message({});
    expect(TDParse.reactionsCanSeeListFrom(shown), isTrue);
    expect(TDParse.message(shown)!.reactionsCanSeeList, isTrue);

    // A capture (or Bot API row) that never carried the flag keeps the list.
    final unmarked = _message({}, canGetAddedReactions: null);
    expect(TDParse.reactionsCanSeeListFrom(unmarked), isTrue);
    expect(TDParse.message(unmarked)!.reactionsCanSeeList, isTrue);
  });

  test('a message without interaction info keeps the list open', () {
    final message = {
      '@type': 'message',
      'id': 2,
      'chat_id': 7,
      'date': 1700000000,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hi'},
      },
    };
    expect(TDParse.reactionsCanSeeListFrom(message), isTrue);
  });
}
