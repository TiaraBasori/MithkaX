import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import '../../components/app_press_ripple.dart';
import '../../components/photo_avatar.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import '../stickers/custom_emoji.dart';
import 'reaction_reactor_avatars.dart';

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
/// Sorting follows the reference too: a private chat leads with the bucket the
/// reader chose, a group/channel with the biggest bucket.
class MessageReactionChips extends StatefulWidget {
  const MessageReactionChips({
    super.key,
    required this.message,
    required this.outgoing,
    this.onToggle,
    this.onShowUsers,
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
    final avatars = _avatarSlot(r, total, fill);
    return GestureDetector(
      key: ValueKey('reactionChip-${widget.message.id}-${_reactionKey(r)}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onToggle?.call(r),
      onLongPress: () => widget.onShowUsers?.call(widget.message, r),
      child: Container(
        height: 26,
        padding: EdgeInsets.only(
          left: 8,
          // 8 + emoji 20 + 4 + count + 8 is the reference chip's box; a lone
          // emoji closes at 31pt (8 + 20 + 3).
          right: avatars == null && r.count <= 1 ? 3 : 8,
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
              const SizedBox(width: 2),
              avatars,
            ] else if (r.count > 1)
              _countTarget(r, foreground),
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
  Widget? _avatarSlot(MessageReaction r, int total, Color fill) {
    if (_isPrivateChat) {
      final me = _meAvatar();
      final peer = _peerAvatar();
      final people = r.count == 2 ? [me, peer] : [if (r.chosen) me else peer];
      if (people.isEmpty) return null;
      return _avatarStack(people, fill);
    }
    if (r.count > 3 || total > 3 || r.reactors.isEmpty) return null;
    return _ReactorAvatarStack(
      key: ValueKey('reactionAvatars-${widget.message.id}-${_reactionKey(r)}'),
      senders: r.reactors.take(3).map((reactor) => reactor.senderId).toList(),
      ringColor: fill,
    );
  }

  Widget _avatarStack(List<_AvatarPerson> people, Color fill) => _AvatarsRow(
    people: people,
    key: ValueKey('reactionAvatars-${widget.message.id}'),
    ringColor: fill,
  );

  _AvatarPerson _meAvatar() =>
      _AvatarPerson(title: widget.meName ?? '', photo: widget.mePhoto);

  _AvatarPerson _peerAvatar() =>
      _AvatarPerson(title: widget.peerTitle ?? '', photo: widget.peerPhoto);

  Widget _countTarget(MessageReaction r, Color color) {
    final count = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '${r.count}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
    final onShow = widget.onShowUsers;
    // Without a list callback the count stays plain text, so the whole chip
    // keeps toggling the reaction exactly as before.
    if (onShow == null) return count;
    return Semantics(
      key: ValueKey('reactionCount-${widget.message.id}-${_reactionKey(r)}'),
      button: true,
      label: AppStrings.t(AppStringKeys.chatReactionUsersCount, {
        'value1': r.count,
      }),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onShow(widget.message, r),
        child: AppPressRipple(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: count,
        ),
      ),
    );
  }

  static String _reactionKey(MessageReaction reaction) =>
      reaction.customEmojiId != 0
      ? 'custom:${reaction.customEmojiId}'
      : 'emoji:${reaction.emoji ?? ''}';
}

/// One 20dp face of the avatar stack.
class _AvatarPerson {
  const _AvatarPerson({required this.title, this.photo});

  final String title;
  final TdFileRef? photo;
}

/// The reference client's overlap: 20dp faces, every further face inset by
/// 16dp, each ringed in the chip's own fill so the stack reads as one pill.
class _AvatarsRow extends StatelessWidget {
  const _AvatarsRow({
    super.key,
    required this.people,
    required this.ringColor,
  });

  final List<_AvatarPerson> people;

  /// The chip fill behind the stack: the 1.5pt ring uses it so overlapping
  /// faces read as one pill on the chosen solid chip and the tinted one alike.
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 1.5),
                ),
                child: PhotoAvatar(
                  title: people[i].title,
                  photo: people[i].photo,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The group/channel variant: resolves each reactor's name and photo through
/// the process-wide cache and paints the same overlapping stack.
class _ReactorAvatarStack extends StatefulWidget {
  const _ReactorAvatarStack({
    super.key,
    required this.senders,
    required this.ringColor,
  });

  final List<int> senders;
  final Color ringColor;

  @override
  State<_ReactorAvatarStack> createState() => _ReactorAvatarStackState();
}

class _ReactorAvatarStackState extends State<_ReactorAvatarStack> {
  final List<ReactionReactorAvatar?> _people = [];

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ReactorAvatarStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSenders(oldWidget.senders, widget.senders)) {
      _people.clear();
      _resolve();
    }
  }

  bool _sameSenders(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _resolve() {
    final cached = [
      for (final id in widget.senders) ReactionReactorAvatars.shared.peek(id),
    ];
    if (cached.every((person) => person != null)) {
      _people
        ..clear()
        ..addAll(cached);
      return;
    }
    for (var i = 0; i < widget.senders.length; i++) {
      final index = i;
      ReactionReactorAvatars.shared
          .resolve(widget.senders[index])
          .then((person) {
            if (!mounted || index >= _people.length) return;
            if (_people[index] == person) return;
            setState(() => _people[index] = person);
          })
          .catchError((_) => null);
    }
    // Keep the row's geometry stable while the lookups are in flight.
    while (_people.length < widget.senders.length) {
      _people.add(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = [
      for (var i = 0; i < widget.senders.length; i++)
        _people.length > i
            ? _AvatarPerson(
                title: _people[i]?.title ?? '',
                photo: _people[i]?.photo,
              )
            : const _AvatarPerson(title: ''),
    ];
    return _AvatarsRow(people: people, ringColor: widget.ringColor);
  }
}
