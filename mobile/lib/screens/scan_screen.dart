import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../engine/off_client.dart';
import '../theme.dart';

/// Barcode → Open Food Facts nutrition lookup. Scan a packaged product (or type
/// its barcode) and see its nutrients and how a portion fits the daily target.
class BarcodeScan {
  /// Opens the scanner, looks the code up in Open Food Facts, and shows the
  /// result. [targets] (kcal/protein) is used for the "% of today" line.
  static Future<void> open(BuildContext context, {Map<String, dynamic>? targets}) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScannerScreen(), fullscreenDialog: true),
    );
    if (code == null || code.trim().isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
        content: Text('Looking up Open Food Facts…')));
    Map<String, dynamic>? product;
    try {
      product = await OffClient().lookup(code);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No internet — barcode lookup needs a connection.')));
      return;
    }
    if (!context.mounted) return;
    if (product == null) {
      messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No usable record for $code in Open Food Facts.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: R.bg2,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ResultSheet(product: product!, targets: targets),
    );
  }
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();
  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA,
      BarcodeFormat.upcE, BarcodeFormat.code128,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manual = TextEditingController();
  bool _handled = false; // pop exactly once

  void _done(String code) {
    if (_handled) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan a barcode'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
                    if (raw != null && raw.trim().isNotEmpty) _done(raw.trim());
                  },
                  errorBuilder: (context, error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Camera unavailable (${error.errorCode.name}).\nType the barcode below instead.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
                // Simple reticle so the user knows where to aim.
                IgnorePointer(
                  child: Container(
                    width: 240,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: R.gold, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: R.bg2,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Point the camera at the barcode, or type it:',
                    style: TextStyle(color: R.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          hintText: 'e.g. 3017620422003', isDense: true),
                      onSubmitted: (v) => v.trim().isNotEmpty ? _done(v.trim()) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () =>
                        _manual.text.trim().isNotEmpty ? _done(_manual.text.trim()) : null,
                    child: const Text('Look up'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the looked-up product's nutrition, scalable to a portion, and how that
/// portion compares with the day's energy/protein target.
class _ResultSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? targets;
  const _ResultSheet({required this.product, required this.targets});
  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  late double grams = _initialGrams();

  double _initialGrams() {
    // Use the OFF serving size if it starts with a number (e.g. "15 g"), else 100 g.
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch('${widget.product['serving_size'] ?? ''}');
    final v = m != null ? double.tryParse(m.group(1)!) : null;
    return (v != null && v > 0 && v <= 2000) ? v : 100;
  }

  double _p(String k) => ((widget.product[k] as num?)?.toDouble() ?? 0) * grams / 100.0;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final kcal = _p('kcal');
    final tgtKcal = (widget.targets?['kcal'] as num?)?.toDouble();
    final tgtProt = (widget.targets?['protein_g'] as num?)?.toDouble();
    final brand = '${p['brand'] ?? ''}';
    String pct(double part, double? whole) =>
        (whole == null || whole == 0) ? '' : '${(part / whole * 100).round()}%';

    Widget macro(String label, double v, Color c, [String unit = 'g']) => Expanded(
          child: Column(children: [
            Text(v.toStringAsFixed(unit == 'g' ? 1 : 0),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: c)),
            Text('$label${unit == 'g' ? ' g' : ''}',
                style: const TextStyle(color: R.muted, fontSize: 10)),
          ]),
        );

    return DraggableScrollableSheet(
      initialChildSize: .62,
      maxChildSize: .9,
      minChildSize: .4,
      expand: false,
      builder: (_, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(18),
        children: [
          Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          if (brand.isNotEmpty)
            Text(brand, style: const TextStyle(color: R.muted, fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Portion', style: TextStyle(color: R.muted, fontSize: 12)),
            const SizedBox(width: 10),
            Expanded(
              child: Slider(
                value: grams.clamp(5, 500),
                min: 5,
                max: 500,
                divisions: 99,
                activeColor: R.gold,
                label: '${grams.round()} g',
                onChanged: (v) => setState(() => grams = v.roundToDouble()),
              ),
            ),
            Text('${grams.round()} g', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: R.surface, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              macro('kcal', kcal, R.gold, 'kcal'),
              macro('Protein', _p('protein'), R.teal),
              macro('Carb', _p('carb'), R.gold),
              macro('Fat', _p('fat'), R.violet),
              macro('Fibre', _p('fibre'), R.green),
            ]),
          ),
          if (tgtKcal != null) ...[
            const SizedBox(height: 12),
            Text(
              '${grams.round()} g is ${pct(kcal, tgtKcal)} of today\'s energy'
              '${tgtProt != null ? ' · ${pct(_p('protein'), tgtProt)} of protein' : ''}.',
              style: const TextStyle(color: R.gold, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.verified_outlined, size: 14, color: R.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('From Open Food Facts (barcode ${p['barcode']}) — community data, per 100 g scaled to your portion.',
                  style: const TextStyle(color: R.muted, fontSize: 11)),
            ),
          ]),
        ],
      ),
    );
  }
}
