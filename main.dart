import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      home: Homescreen(),
    );
  }
}

class Homescreen extends StatefulWidget {
  const Homescreen({super.key});

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {

  Future<Uint8List> createPeoplePdf(List data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('People Data')),

          for (var person in data)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [

                  // LEFT SIDE (TEXT)
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          person['names'],
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(person['location']),
                        pw.SizedBox(height: 4),
                        pw.Text('Interests: ${person['interests']}'),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 10),

                  // RIGHT SIDE (IMAGE)
                  if (person['imageBytes'] != null)
                    pw.Image(
                      pw.MemoryImage(person['imageBytes']),
                      width: 60,
                      height: 60,
                      fit: pw.BoxFit.cover,
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
    var allData = [];

    for (var page = 1; page <= 18; page++) {
      final result = await http.get(
        Uri.parse("https://azimpremjiuniversity.edu.in/people/page/$page"),
      );

      if (result.statusCode == 200) {
        final document = html.parse(result.body);

        for (var li in document.querySelectorAll("ul li")) {
          var name = li.querySelector("h3 a")?.text.trim();

          var location = li
                  .querySelector('div.text-xs.text-green-darker span')
                  ?.text
                  .trim() ??
              '';
          location = location.replaceAll(RegExp(r'\s+'), ' ').trim();

          var interests =
              li.querySelector('div.sm\\:w-4\\/12 p')?.text.trim() ?? '';

          var imgUrl = li.querySelector("img")?.attributes['src'] ?? '';

          Uint8List? imageBytes;

          if (imgUrl.isNotEmpty) {
            try {
              final imgResponse = await http.get(Uri.parse(imgUrl));
              if (imgResponse.statusCode == 200) {
                imageBytes = imgResponse.bodyBytes;
              }
            } catch (e) {
              imageBytes = null;
            }
          }

          if (name != null) {
            allData.add({
              'names': name,
              'interests': interests,
              'location': location,
              'imageBytes': imageBytes,
            });
          }
        }
      }
    }

    final pdfBytes = await createPeoplePdf(allData);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'people_data.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text("Get Member Data of Azim Premji University")),
      floatingActionButton: FloatingActionButton(
        onPressed: getAllData,
        child: Icon(Icons.download),
      ),
    );
  }
}