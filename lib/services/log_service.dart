import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static File? _logFile;

  static Future<void> _ensureFile() async {
    if (_logFile != null) return;
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _logFile = File('${logDir.path}/engreader_$today.log');
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  static Future<void> log(String tag, String message) async {
    try {
      await _ensureFile();
      final line = '[${_timestamp()}][$tag] $message\n';
      await _logFile!.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  static Future<String> getLogPath() async {
    await _ensureFile();
    return _logFile!.path;
  }
}
