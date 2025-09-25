import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'annotate_photo_page.dart';
import 'create_page.dart'; // for ProjectEntry

class TagData {
  final double nx; // 0..1
  final double ny; // 0..1
  final String photoPath; // annotated image file path (absolute)

  TagData({required this.nx, required this.ny, required this.photoPath});

  Map<String, dynamic> toJson() => {'nx': nx, 'ny': ny, 'photoPath': photoPath};
  factory TagData.fromJson(Map<String, dynamic> m) => TagData(
        nx: (m['nx'] as num).toDouble(),
        ny: (m['ny'] as num).toDouble(),
        photoPath: (m['photoPath'] as String?) ?? '',
      );
}

class DetailsPage extends StatefulWidget {
  static const route = '/details';
  const DetailsPage({super.key});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  final _transform = TransformationController();

  // No blueprint image; we just draw on an empty board.
  Size? _boardSize; // set from LayoutBuilder
  late final ProjectEntry _entry;
  final List<TagData> _tags = [];

  // ----- storage (per project) -----
  late final Future<Directory> _projDirFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entry = ModalRoute.of(context)!.settings.arguments as ProjectEntry;
    _projDirFuture = _ensureProjectDir(_entry.id);
    _loadTags(); // fire-and-forget load
  }

  // Project folder: <Docs>/data/projects/<entryId>/
  Future<Directory> _ensureProjectDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'data', 'projects', id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _tagsFile() async {
    final dir = await _projDirFuture;
    final f = File(p.join(dir.path, 'tags.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<void> _saveTags() async {
    try {
      final f = await _tagsFile();
      final jsonStr = jsonEncode(_tags.map((t) => t.toJson()).toList());
      await f.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Save tags failed: $e');
    }
  }

  Future<void> _loadTags() async {
    try {
      final f = await _tagsFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        if (!mounted) return;
        setState(() {
          _tags
            ..clear()
            ..addAll(list.map((e) => TagData.fromJson((e as Map).cast<String, dynamic>())));
        });
      }
    } catch (e) {
      debugPrint('Load tags failed: $e');
    }
  }

  // ----- interactions -----
  void _onTapUp(TapUpDetails d) async {
    if (_boardSize == null) return;

    // Map tap from screen -> board (undo pan/zoom)
    final inverse = Matrix4.inverted(_transform.value);
    final local = MatrixUtils.transformPoint(inverse, d.localPosition);

    final nx = (local.dx / _boardSize!.width).clamp(0.0, 1.0);
    final ny = (local.dy / _boardSize!.height).clamp(0.0, 1.0);

    // Ask for photo source, annotate, save -> then add tag
    final annotatedPath = await _addAnnotatedPhotoFlow();
    if (annotatedPath == null) return;

    setState(() => _tags.add(TagData(nx: nx, ny: ny, photoPath: annotatedPath)));
    await _saveTags();
  }

  Future<void> _onLongPressTag(int index) async {
    // Delete tag on long press
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove tag?'),
        content: const Text('This will remove the pin and its link to the photo (photo file remains).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _tags.removeAt(index));
    await _saveTags();
  }

  // "+" button: allow adding annotated photo even with no tap (drops center pin)
  Future<void> _quickAddPhoto() async {
    final annotatedPath = await _addAnnotatedPhotoFlow();
    if (annotatedPath == null) return;
    const nx = 0.5, ny = 0.5; // centered if no tap
    setState(() => _tags.add(TagData(nx: nx, ny: ny, photoPath: annotatedPath)));
    await _saveTags();
  }

  Future<String?> _addAnnotatedPhotoFlow() async {
    // choose source
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;

    // pick image
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return null;

    // annotate
    final annotatedBytes = await Navigator.push<List<int>?>(
      context,
      MaterialPageRoute(builder: (_) => AnnotatePhotoPage(imagePath: picked.path)),
    );
    if (annotatedBytes == null) return null;

    // save under project/photos/
    final projDir = await _projDirFuture;
    final photosDir = Directory(p.join(projDir.path, 'photos'));
    await photosDir.create(recursive: true);
    final filename = 'ann_${DateTime.now().millisecondsSinceEpoch}.png';
    final absPath = p.join(photosDir.path, filename);
    await File(absPath).writeAsBytes(annotatedBytes);
    return absPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Operation – ${_entry.site}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _quickAddPhoto,
        child: const Icon(Icons.add),
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // empty board we can pan/zoom over
          final board = Size(box.maxWidth, box.maxHeight);
          _boardSize = board;

          return Center(
            child: SizedBox(
              width: board.width,
              height: board.height,
              child: Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 8.0,
                    clipBehavior: Clip.none,
                    child: GestureDetector(
                      onTapUp: _onTapUp,
                      child: Container(
                        width: board.width,
                        height: board.height,
                        color: const Color(0xFFF5F6FA), // light grey board
                        child: const Center(
                          child: Text(
                            'Tap to add a pin • Long-press a pin to delete\nUse + to add photo without a tap',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // pins overlay
                  ..._tags.asMap().entries.map((e) {
                    final i = e.key;
                    final t = e.value;
                    final dx = t.nx * board.width;
                    final dy = t.ny * board.height;
                    return Positioned(
                      left: dx - 14,
                      top: dy - 28,
                      child: GestureDetector(
                        onLongPress: () => _onLongPressTag(i),
                        onTap: () {
                          // preview the annotated photo
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (File(t.photoPath).existsSync())
                                    Image.file(File(t.photoPath), fit: BoxFit.contain),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(p.basename(t.photoPath), style: const TextStyle(fontSize: 12)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                        child: const Icon(Icons.location_on, size: 32, color: Colors.red),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
