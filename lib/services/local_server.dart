import 'dart:io';
import 'package:path/path.dart' as p;

class LocalFileServer {
  HttpServer? _server;
  String? _servingDirectory;
  int _port = 0;

  int get port => _port;
  bool get isRunning => _server != null;

  Future<void> start(String directory) async {
    if (_server != null && _servingDirectory == directory) return;
    await stop();

    _servingDirectory = directory;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen((request) async {
      final path = Uri.decodeComponent(request.uri.path);
      final filePath = p.join(directory, path.substring(1));
      final file = File(filePath);

      if (await file.exists()) {
        final ext = p.extension(filePath).toLowerCase();
        final mimeType = _getMimeType(ext);
        request.response.headers.set('Content-Type', mimeType);
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        await request.response.addStream(file.openRead());
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        request.response.write('Not found');
        await request.response.close();
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _servingDirectory = null;
  }

  String getUrl(String filePath) {
    final relativePath = p.relative(filePath, from: _servingDirectory!);
    return 'http://127.0.0.1:$_port/$relativePath';
  }

  String _getMimeType(String ext) {
    switch (ext) {
      case '.epub':
        return 'application/epub+zip';
      case '.html':
        return 'text/html';
      case '.js':
        return 'application/javascript';
      case '.css':
        return 'text/css';
      case '.json':
        return 'application/json';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.svg':
        return 'image/svg+xml';
      default:
        return 'application/octet-stream';
    }
  }
}
