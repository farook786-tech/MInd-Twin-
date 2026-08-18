import 'dart:typed_data';

import 'export_storage_io.dart'
    if (dart.library.html) 'export_storage_web.dart'
    if (dart.library.js_interop) 'export_storage_web.dart' as impl;

/// Persists generated export bytes and returns a display path.
///
/// On native platforms the file is written to the app documents directory.
/// On web the bytes are handed to the browser as a download, so the returned
/// value is the file name.
Future<String> saveExportFile(String fileName, Uint8List bytes) =>
    impl.saveExportFile(fileName, bytes);
