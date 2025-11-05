
import 'dart:io';
import 'dart:ui' as ui;                  // <-- add this
import 'package:flutter/foundation.dart'; // compute()
import 'package:flutter/material.dart';
import 'package:image_painter/image_painter.dart'; // ^0.7.1
import 'package:path/path.dart' as p;

class AnnotatePhotoPage extends StatefulWidget {
  static const route = '/anotate_photo';
  final String imagePath;
  final String? finalSavePath;

  const AnnotatePhotoPage({
    super.key,
    required this.imagePath,
    this.finalSavePath,
  });

  @override
  State<AnnotatePhotoPage> createState() => _AnnotatePhotoPageState();
}

class _AnnotatePhotoPageState extends State<AnnotatePhotoPage> {
  late final ImagePainterController _controller;
  bool _isSaving = false;

  int _pointerCount = 0;

  // keep a downscaled image in memory for fast interaction
  Uint8List? _previewBytes;

  PaintMode _currentMode  = PaintMode.rect;

  @override
  void initState() {
    super.initState();
    _controller = ImagePainterController()..setMode(PaintMode.rect);
     _controller.addListener(() {
    setState(() {
      _currentMode = _controller.mode;
    });
  });
    // Prepare a smaller, screen-friendly bitmap once up-front
    _preparePreview(); // <-- new
  }

  Future<void> _preparePreview() async {
    // Read original bytes
    final originalBytes = await File(widget.imagePath).readAsBytes();

    // Decode and scale to ~1440px width (keeps aspect)
    const targetWidth = 1440; 
    final codec = await ui.instantiateImageCodec(
      originalBytes,
      targetWidth: targetWidth,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;

    // Re-encode as PNG bytes for ImagePainter.memory
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    setState(() {
      _previewBytes = bd!.buffer.asUint8List();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await Future.delayed(const Duration(milliseconds: 16));

    try {
      // NOTE: exportImage() will export the preview resolution (fast).
      // If/when you need full 12MP export, say the word and I’ll wire a vector replay.
      final Uint8List? bytes = await _controller.exportImage();
      if (!mounted || bytes == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final String targetPath = widget.finalSavePath ?? _makeTempPngPath();
      await compute(_writeBytesToPath, {'bytes': bytes, 'path': targetPath});

      if (!mounted) return;
      Navigator.of(context).pop();                   // close loader
      Navigator.of(context).pop<String>(targetPath); // return path
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _isSaving ? null : _export,
          ),
        ],
      ),

       body: _previewBytes == null
  ? const Center(child: CircularProgressIndicator())
  : Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pointerCount++),
      onPointerUp:   (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
      onPointerCancel: (_) => setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10)),
      child: Stack(
        children: [
          // ImagePainter keeps its own zoom tool & toolbar
          ImagePainter.memory(
            _previewBytes!,
            controller: _controller,
            scalable: true,        // keep this TRUE so the built-in Zoom tool works
            showControls: true,
            controlsAtTop: true,
            colors: const [
              Colors.red, Colors.green, Colors.blue,
              Colors.yellow, Colors.black, Colors.white,
            ],
          ),

          // NEW: transparent overlay that EATS pinch gestures unless Zoom tool is active
          if (_pointerCount >= 2 && _currentMode != PaintMode.none)
            Positioned.fill(
              child: GestureDetector(
                // Capture the gesture so it never reaches ImagePainter.
                onScaleStart: (_) {},
                onScaleUpdate: (_) {},
                onScaleEnd: (_) {},
                // Make sure this actually takes the events:
                behavior: HitTestBehavior.opaque,
              ),
            ),
        ],
      ),
    ),


    );
  }
}

// -------- helpers for compute (top-level) --------

String _makeTempPngPath() {
  final dir = Directory.systemTemp.createTempSync('anno_');
  return p.join(dir.path, 'edited_${DateTime.now().millisecondsSinceEpoch}.png');
}

Future<void> _writeBytesToPath(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final path  = args['path']  as String;
  final f = File(path)..createSync(recursive: true);
  final raf = f.openSync(mode: FileMode.write);
  try {
    raf.writeFromSync(bytes);
    raf.flushSync();
  } finally {
    raf.closeSync();
  }
}
