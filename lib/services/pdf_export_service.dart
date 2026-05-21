import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:engreader/models/annotation.dart';

class PdfExportService {
  static Future<File> exportWithAnnotations({
    required String sourceText,
    required List<Annotation> annotations,
    required String outputPath,
    required String title,
  }) async {
    final pdf = pw.Document();
    final lines = sourceText.split('\n');
    final annotationsByPage = <int, List<Annotation>>{};

    for (final a in annotations) {
      annotationsByPage.putIfAbsent(a.pageIndex, () => []).add(a);
    }

    const linesPerPage = 35;
    final totalPages = (lines.length / linesPerPage).ceil();

    // Title page
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Exported with EngReader',
                  style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey600)),
              pw.SizedBox(height: 10),
              pw.Text('${annotations.length} annotations',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey500)),
            ],
          ),
        ),
      ),
    );

    for (int page = 0; page < totalPages; page++) {
      final startLine = page * linesPerPage;
      final endLine = (startLine + linesPerPage).clamp(0, lines.length);
      final pageLines = lines.sublist(startLine, endLine);
      final pageAnnotations = annotationsByPage[page] ?? [];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(30),
          build: (context) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left: source text
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Page ${page + 1}',
                          style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey500)),
                      pw.SizedBox(height: 8),
                      ...pageLines.map((line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 4),
                            child: pw.Text(line,
                                style: const pw.TextStyle(fontSize: 10)),
                          )),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              // Right: annotations
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber50,
                    border: pw.Border.all(color: PdfColors.amber200),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('批注',
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.amber900)),
                      pw.SizedBox(height: 8),
                      if (pageAnnotations.isEmpty)
                        pw.Text('(无批注)',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500))
                      else
                        ...pageAnnotations.map((a) => pw.Container(
                              margin: const pw.EdgeInsets.only(bottom: 8),
                              padding: const pw.EdgeInsets.all(6),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    '「${a.selectedText}」',
                                    style: pw.TextStyle(
                                        fontSize: 9,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.blue800),
                                  ),
                                  pw.SizedBox(height: 3),
                                  pw.Text(a.translation,
                                      style: const pw.TextStyle(fontSize: 8)),
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
