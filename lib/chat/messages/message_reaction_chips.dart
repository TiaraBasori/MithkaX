import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import '../../components/photo_avatar.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import '../stickers/custom_emoji.dart';
import 'reaction_reactor_avatars.dart';
import 'reaction_toggle.dart';

/// The reaction buckets under a message bubble or media album.
///
/// Laid out the way the reference client draws `ReactionsLayoutInBubble`: one
/// 26dp chip per bucket, a 20dp emoji, a 13sp bold count, a fill at 15.6% of
/// the accent and a pill corner — no border, no big raised pill. The bucket
/// the reader chose is a SOLID accent chip with white ink, exactly like the
/// reference; every other chip keeps the translucent tint. A bucket with at
/// most three reactors (and at most three on the whole message) shows those
/// reactors' overlapping avatars INSTEAD of its number, which is also what the
/// reference client does; in a private chat the two participants stand in for
/// the count.
///
/// A face only appears once its name or photo is known. The reference resolves
/// reactors from its cache synchronously and omits whoever is missing; drawing
/// an empty circle would read as a broken avatar, so an unresolved (or deleted)
/// reactor keeps the count until a real identity arrives.
///
/// Sorting follows the reference too: a private chat leads with the bucket the
/// reader chose, a group/channel with the biggest bucket.
///
/// A tap anywhere on the pill — emoji, count or padding — toggles the bucket;
/// the reactor list is reachable only by a long press, and only where Telegram
/// lets this account enumerate the reactors ([canSeeReactorList], TDLib's
/// `can_get_added_reactions`). A channel's reactions are anonymous, so a long
/// press there stays an ordinary tap.
class MessageReactionChips extends StatefulWidget {
  const MessageReactionChips({
    super.key,
    required this.message,
    required this.outgoing,
    this.onToggle,
    this.onShowUsers,
    this.canSeeReactorList = true,
    this.meId,
    this.meName,
    this.mePhoto,
    this.peerTitle,
    this.peerPhoto,
  });

  final ChatMessage message;
  final bool outgoing;
  final ValueChanged<MessageReaction>? onToggle;
  final void Function(ChatMessage message, MessageReaction reaction)?
  onShowUsers;

  /// Whether the reactor list exists to open. False in a channel, where
  /// reactions are anonymous and TDLib answers no reactors at all.
  final bool canSeeReactorList;

  /// The two participants of a private chat, for the reference client's
  /// two-avatar chips. Absent on cards that never show one.
  final int? meId;
  final String? meName;
  final TdFileRef? mePhoto;
  final String? peerTitle;
  final TdFileRef? peerPhoto;

  @override
  State<MessageReactionChips> createState() => _MessageReactionChipsState();
}

class _MessageReactionChipsState extends State<MessageReactionChips> {
  /// Resolved reactors by sender id. A null value means "asked, no answer
  /// yet"; a failed or deleted sender stays null and never paints a face.
  final Map<int, ReactionReactorAvatar?> _reactors = {};

  @override
  void initState() {
    super.initState();
    _resolveReactors();
  }

  @override
  void didUpdateWidget(covariant MessageReactionChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.message.reactions, widget.message.reactions)) {
      _resolveReactors();
    }
  }

  /// One lookup per distinct reactor, bounded by the three faces a chip can
  /// draw. The cache answers synchronously once warm; a first view fills in as
  /// the profiles arrive.
  void _resolveReactors() {
    for (final reaction in widget.message.reactions) {
      for (final reactor in reaction.reactors.take(3)) {
        final id = reactor.senderId;
        if (id == 0 || _reactors.containsKey(id)) continue;
        final known = ReactionReactorAvatars.shared.peek(id);
        _reactors[id] = known;
        if (known != null) continue;
        ReactionReactorAvatars.shared
            .resolve(id)
            .then((person) {
              if (!mounted) return;
              setState(() => _reactors[id] = person);
            })
            .catchError((_) => null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reactions = _sortedReactions();
    final total = reactions.fold<int>(0, (sum, r) => sum + r.count);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: widget.outgoing ? WrapAlignment.end : WrapAlignment.start,
      children: [for (final r in reactions) _chip(c, r, total)],
    );
  }

  /// A private chat ranks the chosen bucket first (then its own order); a
  /// group/channel ranks by count. `List.sort` is not stable in Dart, so the
  /// original index is the tie-breaker, exactly like the reference comparator's
  /// `compareTied`.
  List<MessageReaction> _sortedReactions() {
    final entries = widget.message.reactions.indexed.toList();
    final privateChat = _isPrivateChat;
    entries.sort((a, b) {
      final (i, first) = a;
      final (j, second) = b;
      if (privateChat) {
        if (first.chosen != second.chosen) return first.chosen ? -1 : 1;
      } else if (first.count != second.count) {
        return second.count.compareTo(first.count);
      }
      return i.compareTo(j);
    });
    return [for (final entry in entries) entry.$2];
  }

  /// Private chats carry positive chat ids; groups and channels live in the
  /// negative bands. A card preview without a chat id keeps the group rule.
  bool get _isPrivateChat {
    final chatId = widget.message.chatId;
    return chatId != null && chatId > 0;
  }

  Widget _chip(AppColors c, MessageReaction r, int total) {
    // Chosen: solid accent with white ink (the reference's selected chip).
    // Others: the accent at 15.6% with the accent as ink.
    final fill = r.chosen
        ? AppTheme.brand
        : AppTheme.brand.withValues(alpha: 0.156);
    final foreground = r.chosen ? Colors.white : AppTheme.brand;
    final avatars = _avatarSlot(r, total);
    final onShow = widget.onShowUsers;
    return GestureDetector(
      key: ValueKey(
        'reactionChip-${widget.message.id}-${reactionBucketKey(r)}',
      ),
      behavior: HitTestBehavior.opaque,
      // The WHOLE pill toggles: the emoji, the count and the padding alike.
      // The reactor list is the long press, and only where it exists.
      onTap: () => widget.onToggle?.call(r),
      onLongPress: widget.canSeeReactorList && onShow != null
          ? () => onShow(widget.message, r)
          : null,
      child: Container(
        height: 26,
        padding: EdgeInsets.only(
          left: 8,
          // 8 + emoji 20 + 4 + count + 8 is the reference chip's box; a lone
          // emoji closes at 31pt (8 + 20 + 3), and an avatar stack keeps the
          // reference's short 4pt tail.
          right: avatars == null ? (r.count <= 1 ? 3 : 8) : 4,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _glyph(r, foreground),
            if (avatars != null) ...[
              const SizedBox(width: 4),
              avatars,
            ] else if (r.count > 1)
              _count(r, foreground),
          ],
        ),
      ),
    );
  }

  Widget _glyph(MessageReaction r, Color color) {
    if (r.customEmojiId != 0) {
      return CustomEmojiView(id: r.customEmojiId, color: color);
    }
    return Text(r.emoji ?? '', style: const TextStyle(fontSize: 20));
  }

  /// The avatars that replace the count, or null when this bucket keeps it.
  ///
  /// Mirrors `ReactionsLayoutInBubble`: a private chat always shows the two
  /// participants (both on a 2-count bucket, otherwise the reader when chosen
  /// and the peer when not); a group/channel only does so while the message has
  /// at most three reactors in total, because beyond that the avatars no longer
  /// name who reacted.
  Widget? _avatarSlot(MessageReaction r, int total) {
    final people = _isPrivateChat
        ? _privateParticipants(r)
        : _resolvedReactors(r, total);
    if (people.isEmpty) return null;
    return _AvatarsRow(
      // The reaction is part of the key: two buckets in one private chat both
      // draw a stack, and duplicate sibling keys break element reuse.
      key: ValueKey(
        'reactionAvatars-${widget.message.id}-${reactionBucketKey(r)}',
      ),
      people: people,
    );
  }

  List<_AvatarPerson> _privateParticipants(MessageReaction r) {
    // No reader id means this surface never told us who is who; the count is
    // the honest thing to show.
    if (widget.meId == null) return const [];
    final me = _AvatarPerson(title: widget.meName ?? '', photo: widget.mePhoto);
    final peer = _AvatarPerson(
      title: widget.peerTitle ?? '',
      photo: widget.peerPhoto,
    );
    final people = r.count == 2 ? [me, peer] : [if (r.chosen) me else peer];
    return [
      for (final person in people)
        if (person.isKnown) person,
    ];
  }

  List<_AvatarPerson> _resolvedReactors(MessageReaction r, int total) {
    if (r.count > 3 || total > 3 || r.reactors.isEmpty) return const [];
    return [
      for (final reactor in r.reactors.take(3))
        if (_reactorPerson(reactor.senderId) case final person?
            when !person.isDeleted && person.title.isNotEmpty)
          _AvatarPerson(title: person.title, photo: person.photo),
    ];
  }

  /// The reader's own face comes from the pane (it already knows the name and
  /// photo), so the avatar the optimistic toggle just prepended paints at once
  /// instead of waiting for a `getUser` round trip. Every other reactor is
  /// resolved lazily through [_reactors].
  ReactionReactorAvatar? _reactorPerson(int senderId) {
    if (widget.meId != null && senderId == widget.meId) {
      final name = widget.meName ?? '';
      if (name.isNotEmpty || widget.mePhoto != null) {
        return ReactionReactorAvatar(title: name, photo: widget.mePhoto);
      }
    }
    return _reactors[senderId];
  }

  /// The count. A plain number now: the whole pill toggles the bucket, so a
  /// tappable number would steal taps meant for the reaction.
  Widget _count(MessageReaction r, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        key: ValueKey(
          'reactionCount-${widget.message.id}-${reactionBucketKey(r)}',
        ),
        label: AppStrings.t(AppStringKeys.chatReactionUsersCount, {
          'value1': r.count,
        }),
        excludeSemantics: true,
        child: Text(
          '${r.count}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// One 20dp face of the avatar stack.
class _AvatarPerson {
  const _AvatarPerson({required this.title, this.photo});

  final String title;
  final TdFileRef? photo;

  /// A face we can actually show: a name, a photo, or both.
  bool get isKnown => title.isNotEmpty || photo != null;
}

/// The reference client's stack: 20dp faces, every further face inset by 16dp,
/// no separator — the earlier face shows through as a crescent, exactly like
/// `AvatarsDrawable` and its 0.8 step. A translucent ring in the chip's fill
/// could not mask the face underneath, so there is none.
class _AvatarsRow extends StatelessWidget {
  const _AvatarsRow({super.key, required this.people});

  final List<_AvatarPerson> people;

  @override
  Widget build(BuildContext context) {
    final size = people.length == 1 ? 20.0 : 20 + (people.length - 1) * 16.0;
    return SizedBox(
      height: 20,
      width: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < people.length; i++)
            Positioned(
              left: i * 16.0,
              top: 0,
              child: SizedBox(
                width: 20,
                height: 20,
                child: PhotoAvatar(
                  title: people[i].title,
                  photo: people[i].photo,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
