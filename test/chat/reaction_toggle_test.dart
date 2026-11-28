//
//  reaction_toggle_test.dart
//
//  The optimistic reaction preview mirrors the reference client's
//  `MessageObject.selectReaction`: an add bumps the bucket, marks it chosen and
//  prepends the reader to its reactors; a remove pops the reader and drops a
//  bucket that reached zero. Pure arithmetic, so it is pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/reaction_toggle.dart';
import 'package:mithka/tdlib/td_models.dart';

const int _meId = 1;

MessageReaction _bucket(
  String emoji,
  int count, {
  bool chosen = false,
  List<int> reactors = const [],
}) => MessageReaction(
  emoji: emoji,
  count: count,
  chosen: chosen,
  reactors: [for (final id in reactors) MessageReactor(senderId: id)],
);

List<int> _ids(List<MessageReaction> reactions, String emoji) => [
  for (final reactor in reactions.firstWhere((r) => r.emoji == emoji).reactors)
    reactor.senderId,
];

void main() {
  test('adds a bucket the message did not carry yet', () {
    final result = previewReactionToggle(const [], _bucket('👍', 0), _meId);

    expect(result, hasLength(1));
    expect(result.single.emoji, '👍');
    expect(result.single.count, 1);
    expect(result.single.chosen, isTrue);
    expect(result.single.reactors.map((r) => r.senderId), [_meId]);
  });

  test('adds to an existing bucket: the reader goes first and is deduped', () {
    final before = [
      _bucket('👍', 2, reactors: [5, _meId, 6]),
    ];

    final result = previewReactionToggle(before, before.single, _meId);

    expect(result.single.count, 3);
    expect(result.single.chosen, isTrue);
    expect(_ids(result, '👍'), [_meId, 5, 6], reason: 'me first, no duplicate');
  });

  test('the preview reactors stay capped at three', () {
    final before = [
      _bucket('👍', 3, reactors: [5, 6, 7]),
    ];

    final result = previewReactionToggle(before, before.single, _meId);

    expect(_ids(result, '👍'), [_meId, 5, 6]);
    expect(result.single.reactors, hasLength(maxReactionPreviewReactors));
  });

  test('removing drops the reader and the chosen flag', () {
    final before = [
      _bucket('👍', 3, chosen: true, reactors: [_meId, 5]),
      _bucket('🔥', 1, reactors: [6]),
    ];

    final result = previewReactionToggle(before, before.first, _meId);

    expect(result, hasLength(2));
    expect(result.first.count, 2);
    expect(result.first.chosen, isFalse);
    expect(result.first.reactors.map((r) => r.senderId), [5]);
    expect(result.last.count, 1, reason: 'other buckets stay untouched');
  });

  test('removing the last reactor drops the whole bucket', () {
    final before = [
      _bucket('👍', 1, chosen: true, reactors: [_meId]),
      _bucket('🔥', 2),
    ];

    final result = previewReactionToggle(before, before.first, _meId);

    expect(result.map((r) => r.emoji), ['🔥']);
  });

  test('a custom emoji bucket is matched by document id, not emoji', () {
    final before = [
      const MessageReaction(customEmojiId: 99, count: 1, chosen: false),
      const MessageReaction(emoji: '👍', count: 1, chosen: false),
    ];

    final result = previewReactionToggle(
      before,
      const MessageReaction(customEmojiId: 99, count: 1, chosen: false),
      _meId,
    );

    expect(result, hasLength(2));
    expect(result.first.customEmojiId, 99);
    expect(result.first.count, 2);
    expect(result.first.chosen, isTrue);
    expect(result.last.count, 1, reason: 'the emoji bucket is a different one');
  });

  test('the input list and its buckets are never mutated', () {
    final bucket = _bucket('👍', 1, reactors: [5]);
    final before = [bucket];

    previewReactionToggle(before, bucket, _meId);

    expect(bucket.count, 1);
    expect(bucket.chosen, isFalse);
    expect(bucket.reactors.map((r) => r.senderId), [5]);
    expect(before.single, same(bucket));
  });
}
