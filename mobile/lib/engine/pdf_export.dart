import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme.dart';

/// Builds a printable PDF of the week's plan (and the grocery list, if supplied),
/// entirely on-device. Every number is taken straight from the plan the engine
/// already computed — nothing is recalculated or invented here. Returns the PDF
/// bytes for `Printing.sharePdf` / `Printing.layoutPdf`.
Future<Uint8List> buildPlanPdf({
  required Map<String, dynamic> plan,
  required Map<String, dynamic> member,
  Map<String, dynamic>? grocery,
}) async {
  // Light palette tuned for white paper (the app's dark theme would waste ink).
  const gold = PdfColor.fromInt(0xFFB07800);
  const green = PdfColor.fromInt(0xFF1E7A4D);
  const ink = PdfColor.fromInt(0xFF1A2420);
  const muted = PdfColor.fromInt(0xFF6B7D74);
  const line = PdfColor.fromInt(0xFFDDE6E1);
  const chip = PdfColor.fromInt(0xFFF2F7F4);

  final days = (plan['days'] as List?) ?? const [];
  final summary = (plan['summary'] as Map?) ?? const {};
  final name = '${member['name'] ?? 'Plan'}';
  final dietGoal =
      '${humanize('${member['diet_type']}')} · ${humanize('${member['goal']}')}';
  final range = days.isEmpty
      ? ''
      : '${prettyDate(days.first['date'])} - ${prettyDate(days.last['date'])}';

  pw.Widget dayCard(Map<String, dynamic> d) {
    final totals = (d['totals'] as Map?) ?? const {};
    final val = (d['validation'] as Map?) ?? const {};
    final entries = (d['entries'] as List?) ?? const [];
    int r(Object? x) => (x as num?)?.round() ?? 0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 7),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(prettyDate(d['date']),
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 11, color: ink)),
          pw.Text(
            '${r(totals['kcal'])} kcal  ·  P ${r(totals['protein'])} g  ·  '
            'Fibre ${r(totals['fibre'])} g  ·  DQS ${val['dqs'] ?? '-'}',
            style: const pw.TextStyle(fontSize: 8.5, color: muted),
          ),
        ]),
        pw.SizedBox(height: 4),
        ...entries.map((e) {
          final comps = (e['components'] as List?) ?? const [];
          if (comps.isEmpty) return pw.SizedBox();
          final names = comps.map((c) => c['name']).join(' + ');
          final kcal = r((e['nutrients'] as Map?)?['kcal']);
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(
                  width: 64,
                  child: pw.Text(slotLabel('${e['slot']}'),
                      style: pw.TextStyle(
                          fontSize: 8.5,
                          color: gold,
                          fontWeight: pw.FontWeight.bold))),
              pw.Expanded(
                  child: pw.Text(names,
                      style: const pw.TextStyle(fontSize: 9, color: ink))),
              pw.Text('$kcal kcal',
                  style: const pw.TextStyle(fontSize: 8.5, color: muted)),
            ]),
          );
        }),
      ]),
    );
  }

  final content = <pw.Widget>[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Rituva',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold, color: gold)),
          pw.Text('Weekly meal plan',
              style: const pw.TextStyle(fontSize: 11, color: muted)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(name,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.Text(dietGoal, style: const pw.TextStyle(fontSize: 9, color: muted)),
          if (range.isNotEmpty)
            pw.Text(range, style: const pw.TextStyle(fontSize: 9, color: muted)),
        ]),
      ],
    ),
    pw.SizedBox(height: 7),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration:
          pw.BoxDecoration(color: chip, borderRadius: pw.BorderRadius.circular(5)),
      child: pw.Text(
        '${summary['on_target'] ?? 0} / ${days.length} days on target  ·  '
        'average diet-quality score ${summary['avg_dqs'] ?? '-'}',
        style: pw.TextStyle(
            fontSize: 9.5, color: green, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.SizedBox(height: 8),
    ...days.map((d) => dayCard(d as Map<String, dynamic>)),
  ];

  if (grocery != null) {
    final cats = (grocery['categories'] as List?) ?? const [];
    content.addAll([
      pw.SizedBox(height: 8),
      pw.Text(
        'Grocery  ·  ${grocery['total_items'] ?? ''} items  ·  ${grocery['people'] ?? ''} people',
        style: pw.TextStyle(
            fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink),
      ),
      pw.SizedBox(height: 2),
      ...cats.expand<pw.Widget>((cat) {
        final items = (cat['items'] as List?) ?? const [];
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
            child: pw.Text('${cat['category']}',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold, color: gold)),
          ),
          pw.Wrap(children: [
            for (final it in items)
              pw.Container(
                width: 168,
                padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                child: pw.Row(children: [
                  pw.Expanded(
                      child: pw.Text('${it['item']}',
                          style: const pw.TextStyle(fontSize: 8.5, color: ink))),
                  pw.Text('${it['quantity']} ${it['unit']}',
                      style: const pw.TextStyle(fontSize: 8.5, color: muted)),
                ]),
              ),
          ]),
        ];
      }),
    ]);
  }

  final doc = pw.Document(title: 'Rituva meal plan - $name', author: 'Rituva');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Every number is computed from the Knowledge DB - guideline-grounded, not medical advice.    ·    '
        '${ctx.pageNumber} / ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 7.5, color: muted),
      ),
    ),
    build: (ctx) => content,
  ));
  return doc.save();
}
