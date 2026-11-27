//
//  reset_database_settings_row.dart
//
//  “重置数据库”: the wide local wipe. Unlike the mirror-only clear it also
//  drops TDLib's message database (each account re-syncs from the server with
//  its session intact), cached media, downloaded emoji packs, the search
//  history and the in-memory image cache — every preference, draft and saved
//  download survives.
//
//  One row, two homes: Data & storage (where a reader looks for a database) and
//  the kept-messages hub (where the mirror switches live). Both must open the
//  same confirm and run the same wipe, so the flow lives here instead of being
//  copied into either page.
//

import 'package:flutter/material.dart';

import '../../components/app_confirm_dialog.dart';
import '../../components/app_icons.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'local_database_reset.dart';

class ResetDatabaseSettingsRow extends StatefulWidget {
  const ResetDatabaseSettingsRow({
    super.key,
    this.rowKey = const ValueKey('settings-reset-database'),
  });

  /// Distinct keys let both settings pages be pumped in one test tree.
  final Key rowKey;

  @override
  State<ResetDatabaseSettingsRow> createState() =>
      _ResetDatabaseSettingsRowState();
}

class _ResetDatabaseSettingsRowState extends State<ResetDatabaseSettingsRow> {
  bool _working = false;

  Future<void> _reset() async {
    if (_working) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.settingsResetDatabase.l10n(context),
      message: AppStringKeys.settingsResetDatabaseMessage.l10n(context),
      confirmText: AppStringKeys.historyClearAction.l10n(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await LocalDatabaseReset.run();
      if (!mounted) return;
      // A failed account keeps its old database (the client rolls back), so the
      // toast must say so instead of claiming the whole reset succeeded.
      showToast(
        context,
        (result.ok
                ? AppStringKeys.settingsResetDatabaseDone
                : AppStringKeys.settingsResetDatabaseFailed)
            .l10n(context),
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: widget.rowKey,
      title: AppStringKeys.settingsResetDatabase.l10n(context),
      subtitle: AppStringKeys.settingsResetDatabaseMessage.l10n(context),
      // The wipe walks every account's database; a spinner-less value keeps
      // the row honest while that runs.
      value: _working ? '…' : '',
      leading: const SettingsLeadingIcon(icon: HeroAppIcons.database),
      titleColor: AppTheme.tagRed,
      enabled: !_working,
      onTap: _reset,
    );
  }
}
