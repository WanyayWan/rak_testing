// lib/pages/annotate_photo_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_painter/image_painter.dart'; // ^0.7.1

class AnnotatePhotoPage extends StatefulWidget {
  static const route = '/anotate_photo';
  final String imagePath;
  const AnnotatePhotoPage({super.key, required this.imagePath});

  @override
  State<AnnotatePhotoPage> createState() => _AnnotatePhotoPageState();
}

class _AnnotatePhotoPageState extends State<AnnotatePhotoPage> {
  late final ImagePainterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ImagePainterController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final bytes = await _controller.exportImage(); // Uint8List?
    if (!mounted || bytes == null) return;
    // Return the edited image bytes to the previous page.
    Navigator.pop<List<int>>(context, bytes);
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
            onPressed: _export,
          ),
        ],
      ),
      body: ImagePainter.file(
        File(widget.imagePath),
        controller: _controller,
        scalable: true,
        showControls: true,
        controlsAtTop: true,
        // Optional: limit/define available colors in the toolbar
        colors: const [
          Colors.red,
          Colors.green,
          Colors.blue,
          Colors.yellow,
          Colors.black,
          Colors.white,
        ],
        // You can also hook into changes:
        // onPaintModeChanged: (mode) {},
        // onColorChanged: (c) {},
        // onStrokeWidthChanged: (w) {},
      ),
    );
  }
}
