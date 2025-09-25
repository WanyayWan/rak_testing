import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Blueprint Kata',
      theme: ThemeData(useMaterial3: true),
      home: const OperationPage(),
    );
  }
}

class TagPoint {
  final double nx; // normalized 0..1
  final double ny;
  const TagPoint(this.nx, this.ny);

  Map<String, dynamic> toJson() => {"nx": nx, "ny": ny};
  factory TagPoint.fromJson(Map<String, dynamic> m) => TagPoint(
        (m["nx"] as num).toDouble(),
        (m["ny"] as num).toDouble(),
      );
}

class OperationPage extends StatefulWidget {
  const OperationPage({super.key});
  @override
  State<OperationPage> createState() => _OperationPageState();
}

class _OperationPageState extends State<OperationPage> {
  final _transform = TransformationController();
  final _imagePath = 'assets/images/blueprint.png';

  Size? _imageIntrinsicSize; // original pixels of the blueprint image
  final List<TagPoint> _tags = [];

  @override
  void initState() {
    super.initState();
    _loadImageSize();
    _loadFromDisk(); // try loading saved pins on start
  }

  Future<void> _loadImageSize() async {
    final bytes = await rootBundle.load(_imagePath);
    final img = await decodeImageFromList(bytes.buffer.asUint8List());
    setState(() => _imageIntrinsicSize = Size(img.width.toDouble(), img.height.toDouble()));
  }

  // Tap mapping: viewport -> image space -> normalized
  void _onTapUp(TapUpDetails d, Size paintSize) {
    // invert pan/zoom
    final inverse = Matrix4.inverted(_transform.value);
    final local = MatrixUtils.transformPoint(inverse, d.localPosition);

    // clamp to the drawn image (fit: contain)
    final nx = (local.dx / paintSize.width).clamp(0.0, 1.0);
    final ny = (local.dy / paintSize.height).clamp(0.0, 1.0);

    setState(() => _tags.add(TagPoint(nx, ny)));
  }

  // Given intrinsic image size and available box, compute contain-fit size
  Size _fitContain(Size img, Size box) {
    final scaleW = box.width / img.width;
    final scaleH = box.height / img.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    return Size(img.width * scale, img.height * scale);
  }

  // ---- Persistence (JSON file in app docs dir) ----
  Future<File> _storageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tags.json');
  }

  Future<void> _saveToDisk() async {
    final f = await _storageFile();
    final jsonStr = jsonEncode(_tags.map((t) => t.toJson()).toList());
    await f.writeAsString(jsonStr);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to local storage')));
  }

  Future<void> _loadFromDisk() async {
    try {
      final f = await _storageFile();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as List;
        setState(() => _tags
          ..clear()
          ..addAll(data.map((e) => TagPoint.fromJson(e as Map<String, dynamic>))));
      }
    } catch (_) {
      // ignore parse errors in this kata
    }
  }

  Future<void> _clearPins() async {
    setState(() => _tags.clear());
  }

  @override
  Widget build(BuildContext context) {
    final intrinsic = _imageIntrinsicSize;
    if (intrinsic == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operation Page (Pan/Zoom + Tap Tags)'),
        actions: [
          IconButton(icon: const Icon(Icons.save_alt), onPressed: _saveToDisk),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFromDisk),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearPins),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final paintSize = _fitContain(intrinsic, Size(box.maxWidth, box.maxHeight));

          return Center(
            child: SizedBox(
              width: paintSize.width,
              height: paintSize.height,
              child: Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 8,
                    clipBehavior: Clip.none,
                    child: GestureDetector(
                      onTapUp: (d) => _onTapUp(d, paintSize),
                      child: Image.asset(_imagePath, fit: BoxFit.contain),
                    ),
                  ),
                  // Overlay the pins (denormalize)
                  ..._tags.map((t) {
                    final dx = t.nx * paintSize.width;
                    final dy = t.ny * paintSize.height;
                    return Positioned(
                      left: dx - 12,
                      top: dy - 24, // shift so the pin tip points to the spot
                      child: const Icon(Icons.location_on, size: 28),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Pins: ${_tags.length} • Long-press save icon if you want to test persistence repeatedly.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}