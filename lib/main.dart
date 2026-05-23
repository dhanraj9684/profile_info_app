import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Homescreen());
}

class Homescreen extends StatefulWidget {
  const Homescreen({super.key});
  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {

  /// Returns the first real http/https URL from a srcset string,
  /// skipping data: URIs and size descriptors like "160w" / "2x".
  String _parseSrcset(String srcset) {
    if (srcset.isEmpty) return '';
    for (final entry in srcset.split(',')) {
      final url = entry.trim().split(RegExp(r'\s+')).first.trim();
      if (url.startsWith('http')) return url; // ← only accept real URLs
    }
    return '';
  }

  String _extractImageUrl(dynamic li) {
    final pictureEl = li.querySelector('picture');
    final imgEl     = li.querySelector('img');
    String imgUrl   = '';

    // 1. <source srcset> / <source data-srcset> inside <picture>
    if (pictureEl != null) {
      for (final source in pictureEl.querySelectorAll('source')) {
        imgUrl = _parseSrcset(source.attributes['srcset'] ?? '')
            .ifEmpty(() => _parseSrcset(source.attributes['data-srcset'] ?? ''));
        if (imgUrl.isNotEmpty) break;
      }
    }

    // 2. <img srcset> / <img data-srcset>
    if (imgUrl.isEmpty && imgEl != null) {
      imgUrl = _parseSrcset(imgEl.attributes['srcset'] ?? '')
          .ifEmpty(() => _parseSrcset(imgEl.attributes['data-srcset'] ?? ''));
    }

    // 3. <img data-src> — strip size descriptor AND reject data: URIs
    if (imgUrl.isEmpty && imgEl != null) {
      final raw = (imgEl.attributes['data-src'] ?? '').trim();
      final candidate = raw.split(RegExp(r'\s+')).first.trim();
      if (candidate.startsWith('http')) imgUrl = candidate;
    }

    // 4. <img src> — reject data: URIs
    if (imgUrl.isEmpty && imgEl != null) {
      final src = (imgEl.attributes['src'] ?? '').trim();
      if (src.startsWith('http')) imgUrl = src;
    }

    // 5. <noscript> fallback
    if (imgUrl.isEmpty) {
      final noscript = li.querySelector('noscript');
      if (noscript != null) {
        final doc = html.parse(noscript.text);
        imgUrl = _parseSrcset(
                doc.querySelector('img')?.attributes['srcset'] ?? '')
            .ifEmpty(() =>
                doc.querySelector('img')?.attributes['src'] ?? '');
        if (!imgUrl.startsWith('http')) imgUrl = '';
      }
    }

    // Fix relative URLs (only if truly relative — not data: URIs)
    if (imgUrl.isNotEmpty &&
        !imgUrl.startsWith('http') &&
        !imgUrl.startsWith('data:')) {
      imgUrl = 'https://azimpremjiuniversity.edu.in$imgUrl';
    }

    print('IMG URL: $imgUrl');
    return imgUrl;
  }

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://azimpremjiuniversity.edu.in/',
  };

  Future<Uint8List> createPeoplePdf(List data) async {
    final pdf = pw.Document();

    // ── Load Unicode fonts ──────────────────────────────────────────────────
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold    = await PdfGoogleFonts.notoSansBold();

    final baseStyle = pw.TextStyle(font: regular, fontSize: 10);
    final boldStyle = pw.TextStyle(font: bold,    fontSize: 11);

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('People Data',
                style: pw.TextStyle(font: bold, fontSize: 18)),
          ),
          for (var person in data)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // LEFT: text
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(person['names'], style: boldStyle),
                        if ((person['location'] as String).isNotEmpty)
                          pw.Text(person['location'], style: baseStyle),
                        pw.SizedBox(height: 4),
                        if ((person['interests'] as String).isNotEmpty)
                          pw.Text('Interests: ${person['interests']}',
                              style: baseStyle),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  // RIGHT: image or placeholder
                  if (person['imageBytes'] != null)
                    pw.ClipOval(
                      child: pw.Image(
                        pw.MemoryImage(person['imageBytes']),
                        width: 60,
                        height: 60,
                        fit: pw.BoxFit.cover,
                      ),
                    )
                  else
                    pw.Container(
                      width: 60,
                      height: 60,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey300,
                        shape: pw.BoxShape.circle,
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          (person['names'] as String)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: pw.TextStyle(font: bold, fontSize: 24),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    return pdf.save();
  }

  void getAllData() async {
    final allData = [];

    for (var page = 1; page <= 18; page++) {
      final result = await http.get(
        Uri.parse('https://azimpremjiuniversity.edu.in/people/page/$page'),
        headers: _headers,
      );

      if (result.statusCode != 200) continue;

      final document = html.parse(result.body);

      for (var li in document.querySelectorAll('ul li')) {
        final name = li.querySelector('h3 a')?.text.trim();
        if (name == null || name.isEmpty) continue;

        var location = li
                .querySelector('div.text-xs.text-green-darker span')
                ?.text
                .trim() ??
            '';
        location = location.replaceAll(RegExp(r'\s+'), ' ').trim();

        final interests =
            li.querySelector('div.sm\\:w-4\\/12 p')?.text.trim() ?? '';

        final imgUrl = _extractImageUrl(li);

        Uint8List? imageBytes;
        if (imgUrl.isNotEmpty) {
          try {
            final imgRes = await http.get(Uri.parse(imgUrl), headers: _headers);
            if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
              imageBytes = imgRes.bodyBytes;
            }
          } catch (e) {
            print('Image fetch error for $name: $e');
          }
        }

        allData.add({
          'names': name,
          'interests': interests,
          'location': location,
          'imageBytes': imageBytes,
        });
      }
    }

    final pdfBytes = await createPeoplePdf(allData);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'people_data.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Text("Click the button below and wait for while to get member's data of Azim Premji University"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: getAllData,
        child: const Icon(Icons.download),
      ),
    );
  }
}

// ── Helper extension ──────────────────────────────────────────────────────────
extension _StringFallback on String {
  String ifEmpty(String Function() fallback) =>
      isEmpty ? fallback() : this;
}