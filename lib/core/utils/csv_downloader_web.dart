// lib/core/utils/csv_downloader_web.dart
// Flutter Web: creates a Blob and triggers a browser download.

import 'dart:js_interop';
import 'package:web/web.dart';

void downloadCsv(String content, String filename) {
  // \uFEFF BOM so Excel auto-detects UTF-8
  final blob = Blob(
    ['\uFEFF$content'.toJS].toJS,
    BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
  );
  final url = URL.createObjectURL(blob);
  final anchor = document.createElement('a') as HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  document.body!.appendChild(anchor);
  anchor.click();
  document.body!.removeChild(anchor);
  URL.revokeObjectURL(url);
}
