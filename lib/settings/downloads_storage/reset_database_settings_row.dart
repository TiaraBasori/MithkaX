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
//  A clean run ends the app: every page in memory was built from the database
//  that is now gone, and repainting them over it is what made the account look
//  signed out until the next launch.
//

import 'package:flutter/material.dart';

import '../../components/app_confirm_dialog.dart';
import '../../components/app_icons.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_exit.dart';
import '../../theme/app_theme.dart';
import 'local_database_reset.dart';

Future<LocalDatabaseResetResult> _runLocalDatabaseReset() =>
    LocalDatabaseReset.run();

class ResetDatabaseSettingsRow extends StatefulWidget {
  const ResetDatabaseSettingsRow({
    super.key,
    this.rowKey = const ValueKey('settings-reset-database'),
    this.runReset = _runLocalDatabaseReset,
    this.quitApp = quitAppProcess,
  });

  /// Distinct keys let both settings pages be pumped in one test tree.
  final Key rowKey;

  /// Runs the wipe; a widget test injects its own to prove the flow without a
  /// live TDLib client.
  final Future<LocalDatabaseResetResult> Function() runReset;

  /// Ends the process after a clean reset. Reports whether it is going away:
  /// iOS cannot terminate itself and must keep the recovered screen.
  final Future<bool> Function() quitApp;

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
      message:
          '${AppStringKeys.settingsResetDatabaseMessage.l10n(context)}\n\n'
          '${AppStringKeys.settingsResetDatabaseExitHint.l10n(context)}',
      confirmText: AppStringKeys.historyClearAction.l10n(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await widget.runReset();
      if (result.ok) {
        // Every page in memory described the database that was just deleted
        // (TDLib reopened each account on a fresh one), so the app ends here
        // instead of repainting half-stale state; the next launch rebuilds.
        // Deliberately not gated on this row still being mounted: the wipe
        // runs on after the page is popped, and the exit is what keeps the
        // half-stale screens from being shown either way.
        final exiting = await widget.quitApp();
        if (!mounted || exiting) return;
      }
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
