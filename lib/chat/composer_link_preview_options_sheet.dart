//
//  composer_link_preview_options_sheet.dart
//
//  The link-preview panel under the composer, shaped like the reply-options
//  sheet: a titled card with the link itself on display, then full-width menu
//  rows. The reply panel's rules apply here too — the on/off row's label and
//  icon flip with the state it will produce the moment it is tapped (no hidden
//  Apply step), and the two position rows name the side the card sits on NOW,
//  with a check on the current one, so tapping one never reads as "move it
//  there" by mistake.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class ComposerLinkPreviewOptionsSheet extends StatefulWidget {
  const ComposerLinkPreviewOptionsSheet({
    super.key,
    required this.url,
    required this.enabled,
    required this.showAboveText,
    required this.onEnabledChanged,
    required this.onPositionChanged,
  });

  /// The first previewable link of the draft.
  final String url;

  final bool enabled;

  /// True when the card renders above the text.
  final bool showAboveText;

  /// Applied immediately, so the banner behind the sheet already reads the
  /// new state when the row is released.
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onPositionChanged;

  @override
  State<ComposerLinkPreviewOptionsSheet> createState() =>
      _ComposerLinkPreviewOptionsSheetState();
}

class _ComposerLinkPreviewOptionsSheetState
    extends State<ComposerLinkPreviewOptionsSheet> {
  late bool _enabled = widget.enabled;
  late bool _above = widget.showAboveText;

  String get _host {
    final uri = Uri.tryParse(widget.url);
    final host = uri?.host ?? '';
    return host.isEmpty ? widget.url : host;
  }

  void _toggleEnabled() {
    setState(() => _enabled = !_enabled);
    widget.onEnabledChanged(_enabled);
  }

  void _setPosition(bool above) {
    if (_above == above) return;
    setState(() => _above = above);
    widget.onPositionChanged(_above);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      key: const ValueKey('composerLinkPreviewOptionsSheet'),
      color: colors.panelBackground,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        // A short window (landscape phone, desktop pane) must scroll the
        // panel instead of overflowing it.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStringKeys.composerLinkPreviewTitle.l10n(context),
                      style: AppTextStyle.title(
                        colors.textPrimary,
                        weight: AppTextWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStringKeys.composerLinkPreviewOptionsSubtitle.l10n(
                        context,
                      ),
                      style: AppTextStyle.body(colors.textSecondary),
                    ),
                  ],
                ),
              ),
              // The link itself, in the reply sheet's preview slot: the host is
              // the title, the URL the subtitle.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  key: const ValueKey('composerLinkPreviewOptionsLink'),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: colors.searchFill,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.link,
                        size: 19,
                        color: _enabled ? colors.linkBlue : colors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.body(
                                _enabled
                                    ? colors.linkBlue
                                    : colors.textTertiary,
                                weight: AppTextWeight.semibold,
                              ),
                            ),
                            Text(
                              widget.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.body(colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _LinkPreviewMenuRow(
                key: ValueKey(
                  _enabled
                      ? 'composerLinkPreviewOptionDisable'
                      : 'composerLinkPreviewOptionEnable',
                ),
                icon: _enabled ? HeroAppIcons.eyeSlash : HeroAppIcons.eye,
                label: _enabled
                    ? AppStringKeys.composerLinkPreviewDisable.l10n(context)
                    : AppStringKeys.composerLinkPreviewEnable.l10n(context),
                onTap: _toggleEnabled,
              ),
              if (_enabled) ...[
                _LinkPreviewMenuRow(
                  key: const ValueKey('composerLinkPreviewOptionAbove'),
                  icon: HeroAppIcons.arrowUp,
                  label: AppStringKeys.composerLinkPreviewAbove.l10n(context),
                  selected: _above,
                  onTap: () => _setPosition(true),
                ),
                _LinkPreviewMenuRow(
                  key: const ValueKey('composerLinkPreviewOptionBelow'),
                  icon: HeroAppIcons.arrowDown,
                  label: AppStringKeys.composerLinkPreviewBelow.l10n(context),
                  selected: !_above,
                  onTap: () => _setPosition(false),
                ),
              ],
              const SizedBox(height: 6),
              _LinkPreviewMenuRow(
                key: const ValueKey('composerLinkPreviewOptionDone'),
                icon: HeroAppIcons.check,
                label: AppStringKeys.composerLinkPreviewOptionDone.l10n(
                  context,
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 48dp menu row: icon, label, full-width tap target, and a trailing check
/// when the row names the state currently in force.
class _LinkPreviewMenuRow extends StatelessWidget {
  const _LinkPreviewMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  /// Draws the trailing check. The position rows use it to say "this is where
  /// the card is now" instead of labelling the move they would perform.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppInteractiveSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              AppIcon(icon, size: 19, color: colors.textSecondary),
              const SizedBox(width: 14),
              Text(
                label,
                style: AppTextStyle.bodyLarge(
                  colors.textPrimary,
                  weight: AppTextWeight.medium,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                AppIcon(HeroAppIcons.check, size: 19, color: colors.linkBlue),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
