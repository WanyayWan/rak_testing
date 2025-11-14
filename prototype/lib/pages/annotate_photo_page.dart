import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_painter/flutter_painter.dart';
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
  late PainterController _controller;
  ui.Image? _backgroundImage;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    // Base controller with settings
    _controller = PainterController(
      settings: PainterSettings(
        // No freehand drawing, only rectangles
        freeStyle: const FreeStyleSettings(
          mode: FreeStyleMode.none,
        ),
        shape: ShapeSettings(
          paint: Paint()
            ..color = Colors.red
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
          // one rectangle per drag
          drawOnce: true,
        ),
        scale: const ScaleSettings(
          enabled: true,
          minScale: 0.5,
          maxScale: 8,
        ),
        // object settings: defaults already allow selecting / transforming
      ),
    );

    // Rebuild when history / selection / settings change
    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    // Load background image
    _initBackground();
  }

  Future<void> _initBackground() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    setState(() {
      _backgroundImage = img;
      _controller.background = img.backgroundDrawable;
      // Use rectangles for shape drawing
      _controller.shapeFactory = RectangleFactory();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------- Toolbar actions ----------

  // Change color for NEW rectangles (and the selected one if any)
  void _setShapeColor(Color color) {
    final current = _controller.settings;
    final currentShape = current.shape;
    final oldPaint = currentShape.paint; // Paint?

    // 1) update settings for future rectangles
    final newPaint = Paint()
      ..color = color
      ..strokeWidth = oldPaint?.strokeWidth ?? 3
      ..style = oldPaint?.style ?? PaintingStyle.stroke
      ..strokeCap = oldPaint?.strokeCap ?? StrokeCap.round;

    _controller.settings = current.copyWith(
      shape: currentShape.copyWith(paint: newPaint),
    );

    // 2) if there is a selected rectangle, apply color immediately
    final selected = _controller.selectedObjectDrawable;
    if (selected is ShapeDrawable) {
      final selOldPaint = selected.paint; // non-null Paint

      final updatedPaint = Paint()
        ..color = color
        ..strokeWidth = selOldPaint.strokeWidth
        ..style = selOldPaint.style
        ..strokeCap = selOldPaint.strokeCap;

      final newShape = selected.copyWith(paint: updatedPaint);
      _controller.replaceDrawable(selected, newShape);
    }
  }

  // Delete currently selected rectangle (if any)
  void _deleteSelected() {
    final selected = _controller.selectedObjectDrawable;
    if (selected != null) {
      _controller.removeDrawable(selected);
    }
  }

  // Clear all rectangles but keep the background image
  void _clearAll() {
    // Remove everything
    _controller.clearDrawables();

    // Re-add the background only
    if (_backgroundImage != null) {
      _controller.background = _backgroundImage!.backgroundDrawable;
    }
  }

  Future<void> _export() async {
    if (_isSaving || _backgroundImage == null) return;
    setState(() => _isSaving = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    // tiny delay so dialog paints
    await Future.delayed(const Duration(milliseconds: 16));

    try {
      final bgSize = Size(
        _backgroundImage!.width.toDouble(),
        _backgroundImage!.height.toDouble(),
      );

      final ui.Image rendered = await _controller.renderImage(bgSize);
      final byteData =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) Navigator.of(context).pop(); // loader
        return;
      }
      final bytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      final targetPath = widget.finalSavePath ?? _makeTempPngPath();
      await compute(_writeBytesToPath, {'bytes': bytes, 'path': targetPath});

      if (!mounted) return;
      Navigator.of(context).pop();                   // close loader
      Navigator.of(context).pop<String>(targetPath); // return path
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // loader
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
    final bg = _backgroundImage;

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
      body: bg == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: AspectRatio(
                aspectRatio: bg.width / bg.height,
                child: FlutterPainter(
                  controller: _controller,
                ),
              ),
            ),

      // Toolbar for undo / clear / delete / colors
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed:
                    _controller.canUndo ? () => _controller.undo() : null,
              ),
              IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed:
                    _controller.canRedo ? () => _controller.redo() : null,
              ),
              IconButton(
                tooltip: 'Clear all rectangles',
                icon: const Icon(Icons.layers_clear),
                onPressed: _clearAll,
              ),
              IconButton(
                tooltip: 'Delete selected',
                icon: const Icon(Icons.delete_outline),
                onPressed: _controller.selectedObjectDrawable != null
                    ? _deleteSelected
                    : null,
              ),
              const SizedBox(width: 8),
              // Color choices
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ColorDot(color: Colors.red, onTap: _setShapeColor),
                    _ColorDot(color: Colors.green, onTap: _setShapeColor),
                    _ColorDot(color: Colors.blue, onTap: _setShapeColor),
                    _ColorDot(color: Colors.yellow, onTap: _setShapeColor),
                    _ColorDot(color: Colors.white, onTap: _setShapeColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small helper widget for color buttons
class _ColorDot extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onTap;

  const _ColorDot({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(color),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
      ),
    );
  }
}

// -------- helpers for compute (unchanged) --------

String _makeTempPngPath() {
  final dir = Directory.systemTemp.createTempSync('anno_');
  return p.join(dir.path, 'edited_${DateTime.now().millisecondsSinceEpoch}.png');
}

Future<void> _writeBytesToPath(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final path = args['path'] as String;
  final f = File(path)..createSync(recursive: true);
  final raf = f.openSync(mode: FileMode.write);
  try {
    raf.writeFromSync(bytes);
    raf.flushSync();
  } finally {
    raf.closeSync();
  }
}
