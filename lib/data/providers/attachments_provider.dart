import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attachments/attachment_remote.dart';
import '../attachments/attachment_store.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

final attachmentStoreProvider = Provider<AttachmentStore>((ref) {
  return AttachmentStore(
    ref.watch(appDatabaseProvider),
    SupabaseAttachmentRemote(ref.watch(supabaseClientProvider)),
  );
});
