import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Simple rectangle model stored as normalized coordinates (0..1)
class RectAnnotation {
  final double nx;   // normalized left
  final double ny;   // normalized top
  final double nw;   // normalized width
  final double nh;   // normalized height
  final Color color;

  const RectAnnotation({
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
    required this.color,
  });

  RectAnnotation copyWith({
    double? nx,
    double? ny,
    double? nw,
    double? nh,
    Color? color,
  }) {
    return RectAnnotation(
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      nw: nw ?? this.nw,
      nh: nh ?? this.nh,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
        'nx': nx,
        'ny': ny,
        'nw': nw,
        'nh': nh,
        'color': color.value,
      };

  factory RectAnnotation.fromJson(Map<String, dynamic> m) => RectAnnotation(
        nx: (m['nx'] as num).toDouble(),
        ny: (m['ny'] as num).toDouble(),
        nw: (m['nw'] as num).toDouble(),
        nh: (m['nh'] as num).toDouble(),
        color: Color((m['color'] as num).toInt()),
      );
}

class AnnotatePhotoPage extends StatefulWidget {
  static const route = '/anotate_photo';
  final String imagePath;      // original or current image
  final String? finalSavePath; // where to save annotated PNG

  const AnnotatePhotoPage({
    super.key,
    required this.imagePath,
    this.finalSavePath,
  });

  @override
  State<AnnotatePhotoPage> createState() => _AnnotatePhotoPageState();
}
enum _DragMode { none, drawing, moving, resizing }

class _AnnotatePhotoPageState extends State<AnnotatePhotoPage> {
  ui.Image? _image;                   // decoded image for painting/export
  bool _isSaving = false;

  // All rectangles (vector objects)
  final List<RectAnnotation> _rects = [];
  int? _selectedIndex;

  // For drawing / moving
  Offset? _dragStartLocal;           // where finger went down (in local coords)
  Offset? _dragStartRectTopLeft;     // starting rect top-left (for moving)
  bool _isMoving = false;
  Rect? _draftRectLocal;             // current drawing rect (local coords)

  _DragMode _dragMode = _DragMode.none;
  Offset? _resizeFixedCornerLocal;   // anchor for resizing
  

  // Current color for new rectangles
  Color _currentColor = Colors.red;

  // For zoom / pan
  final TransformationController _transform = TransformationController();

  // ---------- Helpers for path / JSON ----------

  /// The PNG path we actually save to.
  String get _rasterPath => widget.finalSavePath ?? widget.imagePath;

  /// JSON file path next to the raster image: e.g. foo.png -> foo.rects.json
  String get _jsonPath {
    final dir = File(_rasterPath).parent.path;
    final base = p.basenameWithoutExtension(_rasterPath);
    return p.join(dir, '$base.rects.json');
  }

  @override
  void initState() {
    super.initState();
    _loadImageAndRects();
  }

  Future<void> _loadImageAndRects() async {
    // 1) Decode image (from widget.imagePath, which definitely exists for new photos)
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    // 2) Load existing rects from JSON (if any)
    final jsonFile = File(_jsonPath);
    List<RectAnnotation> loaded = [];
    if (await jsonFile.exists()) {
      try {
        final raw = await jsonFile.readAsString();
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        loaded = list
            .map((e) => RectAnnotation.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList();
      } catch (_) {
        // ignore malformed JSON, just start clean
      }
    }

    if (!mounted) return;
    setState(() {
      _image = img;
      _rects.clear();
      _rects.addAll(loaded);
    });
  }

  Future<void> _saveRectsToJson() async {
    try {
      final f = File(_jsonPath);
      await f.create(recursive: true);
      final raw = jsonEncode(_rects.map((r) => r.toJson()).toList());
      await f.writeAsString(raw);
    } catch (_) {
      // don't crash the UI if save fails
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // ---------- Gesture helpers ----------

  // Hit test: which rectangle (if any) is under this normalized point, topmost first
  int? _hitTestRect(Offset normalized) {
    for (int i = _rects.length - 1; i >= 0; i--) {
      final r = _rects[i];
      final rectN = Rect.fromLTWH(r.nx, r.ny, r.nw, r.nh);
      if (rectN.contains(normalized)) return i;
    }
    return null;
  }
  Offset? _hitResizeHandle(Offset local, Size sceneSize) {
  if (_selectedIndex == null) return null;
  final r = _rects[_selectedIndex!];

  final rectLocal = Rect.fromLTWH(
    r.nx * sceneSize.width,
    r.ny * sceneSize.height,
    r.nw * sceneSize.width,
    r.nh * sceneSize.height,
  );

  // same handle size as painter
  const handleSize = 8.0;
  const hitRadius = 16.0;

  final corners = <Offset>[
    rectLocal.topLeft,
    rectLocal.topRight,
    rectLocal.bottomLeft,
    rectLocal.bottomRight,
  ];

  // if user is near any corner, return the *opposite* corner as the fixed anchor
  Offset? opposite;

  for (int i = 0; i < corners.length; i++) {
    final c = corners[i];
    final d = (local - c).distance;
    if (d <= hitRadius) {
      switch (i) {
        case 0: // topLeft -> opposite is bottomRight
          opposite = rectLocal.bottomRight;
          break;
        case 1: // topRight -> bottomLeft
          opposite = rectLocal.bottomLeft;
          break;
        case 2: // bottomLeft -> topRight
          opposite = rectLocal.topRight;
          break;
        case 3: // bottomRight -> topLeft
          opposite = rectLocal.topLeft;
          break;
      }
      break;
    }
  }

  return opposite; // null if not near any handle
}


  void _onPanStart(Offset local, Size sceneSize) {
  if (_image == null) return;

  _dragStartLocal = local;
  _draftRectLocal = null;
  _dragStartRectTopLeft = null;
  _resizeFixedCornerLocal = null;

  // 1) Check if user grabbed a resize handle on the selected rect
  final fixed = _hitResizeHandle(local, sceneSize);
  if (fixed != null) {
    _dragMode = _DragMode.resizing;
    _resizeFixedCornerLocal = fixed;
    setState(() {}); // just to update selection visuals if needed
    return;
  }

  // 2) Hit test any rect (topmost first)
  final nx = local.dx / sceneSize.width;
  final ny = local.dy / sceneSize.height;
  final hit = _hitTestRect(Offset(nx, ny));

  if (hit != null) {
    // Start moving this rect
    _selectedIndex = hit;
    _dragMode = _DragMode.moving;
    final r = _rects[hit];
    _dragStartRectTopLeft = Offset(
      r.nx * sceneSize.width,
      r.ny * sceneSize.height,
    );
  } else {
    // Start drawing a new rect
    _selectedIndex = null;
    _dragMode = _DragMode.drawing;
    _draftRectLocal = Rect.fromLTWH(local.dx, local.dy, 0, 0);
  }

  setState(() {});
}

void _onPanUpdate(Offset local, Size sceneSize) {
  if (_image == null || _dragStartLocal == null) return;

  switch (_dragMode) {
    case _DragMode.drawing:
      final start = _dragStartLocal!;
      final left = math.min(start.dx, local.dx);
      final top = math.min(start.dy, local.dy);
      final right = math.max(start.dx, local.dx);
      final bottom = math.max(start.dy, local.dy);
      setState(() {
        _draftRectLocal = Rect.fromLTRB(left, top, right, bottom);
      });
      break;

    case _DragMode.moving:
      if (_selectedIndex == null || _dragStartRectTopLeft == null) return;
      final delta = local - _dragStartLocal!;
      final newTopLeft = _dragStartRectTopLeft! + delta;

      setState(() {
        final old = _rects[_selectedIndex!];
        final nx = (newTopLeft.dx / sceneSize.width).clamp(0.0, 1.0);
        final ny = (newTopLeft.dy / sceneSize.height).clamp(0.0, 1.0);
        _rects[_selectedIndex!] = old.copyWith(nx: nx, ny: ny);
      });
      break;

    case _DragMode.resizing:
      if (_selectedIndex == null || _resizeFixedCornerLocal == null) return;

      // Create rect between fixed corner and current finger
      var rLocal = Rect.fromPoints(_resizeFixedCornerLocal!, local);

      // Clamp inside image bounds
      rLocal = Rect.fromLTWH(
        rLocal.left.clamp(0.0, sceneSize.width),
        rLocal.top.clamp(0.0, sceneSize.height),
        (rLocal.width).clamp(1.0, sceneSize.width),
        (rLocal.height).clamp(1.0, sceneSize.height),
      );

      setState(() {
        final nx = (rLocal.left / sceneSize.width).clamp(0.0, 1.0);
        final ny = (rLocal.top / sceneSize.height).clamp(0.0, 1.0);
        final nw = (rLocal.width / sceneSize.width).clamp(0.0, 1.0);
        final nh = (rLocal.height / sceneSize.height).clamp(0.0, 1.0);
        final old = _rects[_selectedIndex!];
        _rects[_selectedIndex!] = old.copyWith(nx: nx, ny: ny, nw: nw, nh: nh);
      });
      break;

    case _DragMode.none:
      break;
  }
}

void _onPanEnd(Size sceneSize) {
  if (_image == null) return;

  if (_dragMode == _DragMode.drawing && _draftRectLocal != null) {
    final r = _draftRectLocal!;

    if (r.width >= 4 && r.height >= 4) {
      final nx = (r.left / sceneSize.width).clamp(0.0, 1.0);
      final ny = (r.top / sceneSize.height).clamp(0.0, 1.0);
      final nw = (r.width / sceneSize.width).clamp(0.0, 1.0);
      final nh = (r.height / sceneSize.height).clamp(0.0, 1.0);

      setState(() {
        _rects.add(RectAnnotation(
          nx: nx,
          ny: ny,
          nw: nw,
          nh: nh,
          color: _currentColor,
        ));
        _selectedIndex = _rects.length - 1;
        _draftRectLocal = null;
      });
      _saveRectsToJson();
    } else {
      setState(() => _draftRectLocal = null);
    }
  } else if (_dragMode == _DragMode.moving ||
             _dragMode == _DragMode.resizing) {
    _saveRectsToJson();
  }

  _dragMode = _DragMode.none;
  _dragStartLocal = null;
  _dragStartRectTopLeft = null;
  _resizeFixedCornerLocal = null;
}


  // ---------- Toolbar actions ----------

  void _setColor(Color color) {
    setState(() {
      _currentColor = color;
      if (_selectedIndex != null) {
        final r = _rects[_selectedIndex!];
        _rects[_selectedIndex!] = r.copyWith(color: color);
        _saveRectsToJson();
      }
    });
  }

  void _deleteSelected() {
    if (_selectedIndex == null) return;
    setState(() {
      _rects.removeAt(_selectedIndex!);
      _selectedIndex = null;
    });
    _saveRectsToJson();
  }

  void _clearAll() {
    setState(() {
      _rects.clear();
      _selectedIndex = null;
      _draftRectLocal = null;
    });
    _saveRectsToJson();
  }

  void _undo() {
    if (_rects.isEmpty) return;
    setState(() {
      _rects.removeLast();
      _selectedIndex = null;
    });
    _saveRectsToJson();
  }

  // ---------- Export PNG with rectangles baked in ----------

  Future<void> _export() async {
    if (_isSaving || _image == null) return;
    setState(() => _isSaving = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await Future.delayed(const Duration(milliseconds: 16));

    try {
      final img = _image!;
      final size = Size(img.width.toDouble(), img.height.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw base image
      final src = Rect.fromLTWH(0, 0, size.width, size.height);
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(img, src, dst, Paint());

      // Draw all rectangles scaled to the real image resolution
      for (final r in _rects) {
        final rect = Rect.fromLTWH(
          r.nx * size.width,
          r.ny * size.height,
          r.nw * size.width,
          r.nh * size.height,
        );
        final paint = Paint()
          ..color = r.color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawRect(rect, paint);
      }

      final picture = recorder.endRecording();
      final outImage =
          await picture.toImage(img.width, img.height); // full-res render

      final byteData =
          await outImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) Navigator.of(context).pop(); // loader
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      final targetPath = _rasterPath;
      await compute(_writeBytesToPath, {'bytes': pngBytes, 'path': targetPath});
      await _saveRectsToJson();

      if (!mounted) return;
      Navigator.of(context).pop(); // close loader
      Navigator.of(context).pop<String>(targetPath); // return path as before
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final img = _image;

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
      body: img == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (ctx, constraints) {
                final imageSize =
                    Size(img.width.toDouble(), img.height.toDouble());
                final viewportSize =
                    Size(constraints.maxWidth, constraints.maxHeight);

                // Fit image into available space (BoxFit.contain)
                final fitted =
                    applyBoxFit(BoxFit.contain, imageSize, viewportSize);
                final sceneSize = fitted.destination;

                return Center(
                  child: SizedBox(
                    width: sceneSize.width,
                    height: sceneSize.height,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 0.5,
                      maxScale: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) =>
                            _onPanStart(d.localPosition, sceneSize),
                        onPanUpdate: (d) =>
                            _onPanUpdate(d.localPosition, sceneSize),
                        onPanEnd: (_) => _onPanEnd(sceneSize),
                        child: CustomPaint(
                          size: sceneSize,
                          painter: _AnnotPainter(
                            image: img,
                            rects: _rects,
                            selectedIndex: _selectedIndex,
                            draftRectLocal: _draftRectLocal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Undo last rectangle',
                icon: const Icon(Icons.undo),
                onPressed: _rects.isNotEmpty ? _undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out_map),
                onPressed: () {
                  _transform.value = Matrix4.identity();
                },
              ),

              IconButton(
                tooltip: 'Clear all rectangles',
                icon: const Icon(Icons.layers_clear),
                onPressed: _rects.isNotEmpty ? _clearAll : null,
              ),
              IconButton(
                tooltip: 'Delete selected',
                icon: const Icon(Icons.delete_outline),
                onPressed: _selectedIndex != null ? _deleteSelected : null,
              ),
              const SizedBox(width: 8),
              // Color choices
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ColorDot(
                      color: Colors.red,
                      onTap: _setColor,
                      selected: _currentColor == Colors.red,
                    ),
                    _ColorDot(
                      color: Colors.green,
                      onTap: _setColor,
                      selected: _currentColor == Colors.green,
                    ),
                    _ColorDot(
                      color: Colors.blue,
                      onTap: _setColor,
                      selected: _currentColor == Colors.blue,
                    ),
                    _ColorDot(
                      color: Colors.yellow,
                      onTap: _setColor,
                      selected: _currentColor == Colors.yellow,
                    ),
                    _ColorDot(
                      color: Colors.white,
                      onTap: _setColor,
                      selected: _currentColor == Colors.white,
                    ),
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

/// Draws the photo + all rectangles.
class _AnnotPainter extends CustomPainter {
  final ui.Image image;
  final List<RectAnnotation> rects;
  final int? selectedIndex;
  final Rect? draftRectLocal;

  _AnnotPainter({
    required this.image,
    required this.rects,
    required this.selectedIndex,
    required this.draftRectLocal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgSize = Size(image.width.toDouble(), image.height.toDouble());

    // Draw image scaled to fit exactly the available size (we already computed contain)
    final src = Rect.fromLTWH(0, 0, imgSize.width, imgSize.height);
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());

    // Draw stored rectangles
    for (int i = 0; i < rects.length; i++) {
      final r = rects[i];
      final rect = Rect.fromLTWH(
        r.nx * size.width,
        r.ny * size.height,
        r.nw * size.width,
        r.nh * size.height,
      );
      final isSel = (i == selectedIndex);
      final paint = Paint()
        ..color = r.color
        ..strokeWidth = isSel ? 4 : 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawRect(rect, paint);

      // Optional: draw little "handles" for selected rect
      if (isSel) {
        final handlePaint = Paint()
          ..color = r.color.withOpacity(0.9)
          ..style = PaintingStyle.fill;
        const handleSize = 8.0;
        for (final pt in [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ]) {
          canvas.drawRect(
            Rect.fromCenter(center: pt, width: handleSize, height: handleSize),
            handlePaint,
          );
        }
      }
    }

    // Draw the in-progress rectangle (while dragging)
    if (draftRectLocal != null) {
      final draftPaint = Paint()
        ..color = Colors.red.withOpacity(0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawRect(draftRectLocal!, draftPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.rects != rects ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.draftRectLocal != draftRectLocal;
  }
}

/// Small helper widget for color buttons
class _ColorDot extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onTap;
  final bool selected;

  const _ColorDot({
    required this.color,
    required this.onTap,
    required this.selected,
  });

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
          border: Border.all(
            color: selected ? Colors.black : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

// -------- helpers for compute (unchanged idea) --------

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
