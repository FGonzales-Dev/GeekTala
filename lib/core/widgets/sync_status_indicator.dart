import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/sync_provider.dart';
import '../../data/sync/app_sync_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/relative_time.dart';

/// `.sync-status` — a colored dot plus a short status string: what's
/// waiting to upload, or when this device last synced (`syncStatusProvider`,
/// see lib/data/sync/sync_service.dart).
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nooteColors;
    final status = ref.watch(syncStatusProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: _dotColor(status, colors),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _label(status),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.syncStatus.copyWith(color: colors.textFaint),
          ),
        ),
      ],
    );
  }

  Color _dotColor(AppSyncStatus status, NooteColors colors) {
    if (status.busy) return colors.avatar2;
    if (status.hasError) return Colors.red;
    if (status.pendingChanges > 0) return Colors.amber.shade700;
    return colors.avatar1;
  }

  String _label(AppSyncStatus status) {
    if (status.uploading) return 'Uploading…';
    if (status.downloading) return 'Downloading…';
    if (status.hasError) return 'Sync failed';
    final pending = status.pendingChanges;
    if (pending > 0) {
      return '$pending ${pending == 1 ? 'change' : 'changes'} not uploaded';
    }
    final lastSyncedAt = status.lastSyncedAt;
    if (lastSyncedAt == null) return 'Not synced yet';
    return 'Synced ${formatRelativeTime(lastSyncedAt, DateTime.now())}';
  }
}
