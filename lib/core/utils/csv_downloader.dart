// lib/core/utils/csv_downloader.dart
// Conditional export: triggers a file download on web, no-op elsewhere.

export 'csv_downloader_stub.dart'
    if (dart.library.html) 'csv_downloader_web.dart';
