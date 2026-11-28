//
//  reaction_toggle.dart
//
//  The reader's own reaction, applied to the chip row before TDLib answers.
//
//  The reference client does the same in `MessageObject.selectReaction`: the
//  tap increments the bucket, marks it chosen and — because the reader is the
//  newest reactor — puts their own `messagePeerReaction` at index 0 of the
//  recent list, so the avatar stack shows the reader's face at once instead of
//  waiting for a round trip. Removing pops that entry and drops the bucket when
//  its count reaches zero.
//
//  Kept pure so the transcript can apply it optimistically and a test can pin
//  the arithmetic without a client.

import '../../tdlib/td_models.dart';

/// How many reactors a chip can draw; the reference's `recent_sender_ids` cap.
const int maxReactionPreviewReactors = 3;

/// The identity of a reaction bucket: a custom emoji by document id, otherwise
/// by its emoji. Two buckets that render the same chip share this key.
String reactionBucketKey(MessageReaction reaction) =>
    reaction.customEmojiId != 0
    ? 'custom:${reaction.customEmojiId}'
    : 'emoji:${reaction.emoji ?? ''}';

/// Returns a new list with [tapped]'s bucket toggled for the reader [meId].
///
/// A tap on a bucket the reader has not chosen ADDS: count + 1, chosen, and the
/// reader prepended to the reactors (deduplicated, capped at
/// [maxReactionPreviewReactors]). The bucket is appended when the list did not
/// carry it yet, exactly like the reference's `results.add`.
///
/// A tap on a chosen bucket REMOVES: count - 1, chosen false, the reader
/// dropped from the reactors, and the whole bucket dropped once its count
/// reaches zero. [tapped] itself is never mutated and other buckets keep their
/// identity.
List<MessageReaction> previewReactionToggle(
  List<MessageReaction> reactions,
  MessageReaction tapped,
  int meId,
) {
  final key = reactionBucketKey(tapped);
  final index = reactions.indexWhere((r) => reactionBucketKey(r) == key);

  if (tapped.chosen) {
    if (index < 0) return List<MessageReaction>.of(reactions);
    final current = reactions[index];
    final count = current.count > 0 ? current.count - 1 : 0;
    if (count <= 0) {
      return [
        for (final r in reactions)
          if (reactionBucketKey(r) != key) r,
      ];
    }
    final next = List<MessageReaction>.of(reactions);
    next[index] = current.copyWith(
      count: count,
      chosen: false,
      reactors: [
        for (final reactor in current.reactors)
          if (meId == 0 || reactor.senderId != meId) reactor,
      ],
    );
    return next;
  }

  final me = meId > 0
      ? <MessageReactor>[MessageReactor(senderId: meId)]
      : const <MessageReactor>[];
  if (index < 0) {
    return [
      ...reactions,
      tapped.copyWith(count: tapped.count + 1, chosen: true, reactors: me),
    ];
  }
  final current = reactions[index];
  final next = List<MessageReaction>.of(reactions);
  next[index] = current.copyWith(
    count: current.count + 1,
    chosen: true,
    reactors: [
      ...me,
      for (final reactor in current.reactors)
        if (meId == 0 || reactor.senderId != meId) reactor,
    ].take(maxReactionPreviewReactors).toList(),
  );
  return next;
}
