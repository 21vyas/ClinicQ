// lib/core/utils/csv_downloader_stub.dart
// Mobile/Desktop: writes CSV to temp storage, then opens native share/save UI.

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void downloadCsv(String content, String filename) {
  unawaited(_saveAndShareCsv(content, filename));
}

Future<void> _saveAndShareCsv(String content, String filename) async {
  try {
    final sanitized = filename.trim().isEmpty ? 'patients.csv' : filename.trim();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$sanitized');

    // Prefix with BOM so spreadsheet apps detect UTF-8 consistently.
    await file.writeAsString('\uFEFF$content', flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        title: 'Export CSV',
        subject: sanitized,
        text: 'ClinicQ patient export',
      ),
    );
  } catch (_) {
    // Keep this utility fire-and-forget for UI callers.
  }
}
