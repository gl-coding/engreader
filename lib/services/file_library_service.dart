import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Imports user-selected files into the app's sandbox so native PlatformViews
/// can read them freely without requiring per-call security-scoped access.
class FileLibraryService {
  static const _libraryDirName = 'library';

  static Future<Directory> _getLibraryDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final libDir = Directory(p.join(appDir.path, _libraryDirName));
    if (!libDir.existsSync()) {
      libDir.createSync(recursive: true);
    }
    return libDir;
  }

  /// Imports an external file by copying it into the app's sandbox library.
  /// Returns the new path inside the sandbox.
  static Future<String> importFile(String externalPath) async {
    final libDir = await _getLibraryDir();
    final original = File(externalPath);
    final fileName = p.basename(externalPath);

    var destPath = p.join(libDir.path, fileName);
    final destFile = File(destPath);

    if (destFile.existsSync()) {
      final externalSize = await original.length();
      final destSize = await destFile.length();
      if (externalSize == destSize) {
        return destPath;
      }
      final base = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      destPath = p.join(libDir.path, '${base}_$timestamp$ext');
    }

    await original.copy(destPath);
    return destPath;
  }

  /// Whether a file path is inside the app's library (already imported).
  static Future<bool> isInLibrary(String path) async {
    final libDir = await _getLibraryDir();
    return p.isWithin(libDir.path, path);
  }

  /// Lists all files currently in the library.
  static Future<List<String>> listLibraryFiles() async {
    final libDir = await _getLibraryDir();
    return libDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((path) {
          final ext = p.extension(path).toLowerCase();
          return ext == '.pdf' || ext == '.txt' || ext == '.epub';
        })
        .toList();
  }

  static Future<void> deleteFromLibrary(String path) async {
    final inLibrary = await isInLibrary(path);
    if (!inLibrary) return;
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
