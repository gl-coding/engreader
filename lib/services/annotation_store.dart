import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:engreader/models/annotation.dart';

class AnnotationStore {
  static Future<String> _getStorePath(String filePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final annotationsDir = Directory(p.join(dir.path, 'engreader_annotations'));
    if (!annotationsDir.existsSync()) {
      annotationsDir.createSync(recursive: true);
    }
    final hash = filePath.hashCode.toRadixString(16);
    return p.join(annotationsDir.path, '$hash.json');
  }

  static Future<List<Annotation>> load(String filePath) async {
    final storePath = await _getStorePath(filePath);
    final file = File(storePath);
    if (!file.existsSync()) return [];

    final content = await file.readAsString();
    final list = jsonDecode(content) as List;
    return list
        .map((e) => Annotation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(
      String filePath, List<Annotation> annotations) async {
    final storePath = await _getStorePath(filePath);
    final file = File(storePath);
    final json = annotations.map((a) => a.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
  }

  static Future<void> addAnnotation(
      String filePath, Annotation annotation) async {
    final annotations = await load(filePath);
    annotations.add(annotation);
    await save(filePath, annotations);
  }

  static Future<void> removeAnnotation(String filePath, String id) async {
    final annotations = await load(filePath);
    annotations.removeWhere((a) => a.id == id);
    await save(filePath, annotations);
  }
}
