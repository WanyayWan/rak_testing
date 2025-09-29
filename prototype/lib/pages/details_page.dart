import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'annotate_photo_page.dart';
import 'create_page.dart'; // for ProjectEntry

// ---------- Models (per-project) ----------

class Defect {
  final String photoPath;   // annotated photo (absolute)
  final String priority;    // "LOW", "MED", "HIGH"
  final String note;

  Defect({required this.photoPath, required this.priority, required this.note});

  Map<String, dynamic> toJson() => {
        'photoPath': photoPath,
        'priority': priority,
        
        'note': note,
      };

  factory Defect.fromJson(Map<String, dynamic> m) => Defect(
        photoPath: (m['photoPath'] as String?) ?? '',
        priority: (m['priority'] as String?) ?? 'LOW',
        note: (m['note'] as String?) ?? '',
      );
}

class PinData {
  final double nx; // 0..1
  final double ny; // 0..1
  String label;
  final List<Defect> defects;

  PinData({required this.nx, required this.ny, required this.label, required this.defects});

  Map<String, dynamic> toJson() => {
        'nx': nx,
        'ny': ny,
        'label': label,
        'defects': defects.map((d) => d.toJson()).toList(),
      };

  factory PinData.fromJson(Map<String, dynamic> m) => PinData(
        nx: (m['nx'] as num).toDouble(),
        ny: (m['ny'] as num).toDouble(),
        label: (m['label'] as String?) ?? 'A?',
        defects: (m['defects'] as List? ?? [])
            .map((e) => Defect.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

// ---------- Page ----------

class DetailsPage extends StatefulWidget {
  static const route = '/details';
  const DetailsPage({super.key});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  bool _initialized = false; 
  late final ProjectEntry _entry;
  final _transform = TransformationController();

  Size? _imgDrawnSize; // the size the blueprint is drawn at (for tap mapping)
  final List<PinData> _pins = [];

  late final Future<Directory> _projDirFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;               // <-- guard: run once
    _initialized = true;
    
    _entry = ModalRoute.of(context)!.settings.arguments as ProjectEntry;
    _projDirFuture = _ensureProjectDir(_entry.id);
    _loadPins();
  }

  // ---------- Storage (per project) ----------

  Future<Directory> _ensureProjectDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'data', 'projects', id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _pinsFile() async {
    final dir = await _projDirFuture;
    final f = File(p.join(dir.path, 'tags.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<Directory> _photosDir() async {
    final dir = await _projDirFuture;
    final photos = Directory(p.join(dir.path, 'photos'));
    await photos.create(recursive: true);
    return photos;
  }

  Future<void> _savePins() async {
    try {
      final f = await _pinsFile();
      final jsonStr = jsonEncode(_pins.map((p) => p.toJson()).toList());
      await f.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Save pins failed: $e');
    }
  }

  Future<void> _loadPins() async {
    try {
      final f = await _pinsFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        if (!mounted) return;
        setState(() {
          _pins
            ..clear()
            ..addAll(list.map((e) => PinData.fromJson((e as Map).cast<String, dynamic>())));
        });
      }
    } catch (e) {
      debugPrint('Load pins failed: $e');
    }
  }

  String _nextLabel() => 'A${_pins.length + 1}';
  // ---------- Tap / Long-press interactions ----------

  void _onTapUp(TapUpDetails d) async {
     if (_imgDrawnSize == null) return;

  final inverse = Matrix4.inverted(_transform.value);
  final local = MatrixUtils.transformPoint(inverse, d.localPosition);

  final nx = (local.dx / _imgDrawnSize!.width).clamp(0.0, 1.0);
  final ny = (local.dy / _imgDrawnSize!.height).clamp(0.0, 1.0);

  // 1) Optimistic: show pin immediately
  final tempPin = PinData(nx: nx, ny: ny, label: _nextLabel(), defects: []);
  setState(() => _pins.add(tempPin));

  // 2) Run capture+annotate flow
  final defect = await _captureAndAnnotateDefect();

  if (!mounted) return;

  if (defect == null) {
    // 3) User cancelled: remove the temp pin
    setState(() => _pins.remove(tempPin));
    return;
  }

  // 4) Success: attach first defect and persist
  setState(() => tempPin.defects.add(defect));
  await _savePins();
}

  Future<void> _onLongPressPin(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete pin?'),
        content: const Text('This removes the pin and its defect links (photos remain on disk).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _pins.removeAt(index));
    await _savePins();
  }

  // Tapping a pin opens its defect list (bottom sheet) with add/delete
  void _openPinSheet(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final pin = _pins[index];
        return StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16, right: 16, top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                            Row(
              children: [
                Text('Pin ${_pins[index].label}  •  Defects: ${pin.defects.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Rename pin',
                  onPressed: () async {
                    final newLabel = await showDialog<String>(
                      context: context,
                      builder: (_) {
                        final ctrl = TextEditingController(text: _pins[index].label);
                        return AlertDialog(
                          title: const Text('Rename pin'),
                          content: TextField(
                            controller: ctrl,
                            decoration: const InputDecoration(
                              labelText: 'Label (e.g., A3)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
                          ],
                        );
                      },
                    );
                    if (newLabel != null && newLabel.isNotEmpty) {
                      setState(() => _pins[index].label = newLabel);
                      setModal(() {});       // refresh the sheet UI
                      await _savePins();     // persist change
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate),
                  tooltip: 'Add defect',
                  onPressed: () async {
                    final d = await _captureAndAnnotateDefect();
                    if (d == null) return;
                    setState(() => _pins[index].defects.add(d));
                    setModal(() {});
                    await _savePins();
                  },
                ),
              ],
            ),
                const SizedBox(height: 8),
                ...pin.defects.asMap().entries.map((e) {
                  final i = e.key;
                  final d = e.value;
                  return Card(
                    child: ListTile(
                      leading: File(d.photoPath).existsSync()
                          ? Image.file(File(d.photoPath), width: 48, height: 48, fit: BoxFit.cover)
                          : const Icon(Icons.broken_image),
                      title: Text(d.priority),
                      subtitle: Text(d.note.isEmpty ? '(no note)' : d.note, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () async {
                          setState(() => _pins[index].defects.removeAt(i));
                          setModal(() {});
                          await _savePins();
                        },
                      ),
                      onTap: () {
                        // preview
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (File(d.photoPath).existsSync())
                                  Image.file(File(d.photoPath), fit: BoxFit.contain),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text('Priority: ${d.priority}\n${d.note}'),
                                ),
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          );
        });
      },
    );
  }

  // ---------- Defect capture + annotate + meta ----------

  Future<Defect?> _captureAndAnnotateDefect() async {
    // 1) choose source
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

    // 2) pick
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (picked == null) return null;

    // 3) annotate
    final annotatedBytes = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnnotatePhotoPage(imagePath: picked.path)),
    ) as List<int>?; // works with Uint8List too
    if (annotatedBytes == null) return null;

    // 4) save file to project/photos
    final photosDir = await _photosDir();
    final filename = 'ann_${DateTime.now().millisecondsSinceEpoch}.png';
    final absPath = p.join(photosDir.path, filename);
    await File(absPath).writeAsBytes(annotatedBytes);

    // 5) collect priority + note (with confirmation + defaults)
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final noteCtrl = TextEditingController();
        String? priority; // start as null to detect "not chosen"
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16, right: 16, top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Defect details', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: priority,
                items: const [
                  DropdownMenuItem(value: 'LOW', child: Text('LOW PRIORITY')),
                  DropdownMenuItem(value: 'MED', child: Text('MED PRIORITY')),
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH PRIORITY')),
                ],
                onChanged: (v) => priority = v,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  String? p = priority;
                  String n = noteCtrl.text.trim();

                  // If either empty -> ask confirmation then fill defaults
                  if (p == null || p.isEmpty || n.isEmpty) {
                    final ok = await _confirmSaveWithDefaults();
                    if (!ok) return; // stay on sheet
                    p ??= 'LOW';
                    if (n.isEmpty) n = 'No remarks provided';
                  }

                  // Return values to caller
                  // (Sheet will close here)
                  // Use a map to keep current structure
                  // Keys: priority, note
                  Navigator.pop(ctx, {'priority': p, 'note': n});
                },
                child: const Text('SAVE'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (result == null) return null;

    return Defect(
      photoPath: absPath,
      priority: result['priority'] ?? 'LOW',
      note: (result['note']?.trim().isEmpty ?? true) ? 'No remarks provided' : result['note']!.trim(),
    );
  }

Future<bool> _confirmSaveWithDefaults() async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Save with defaults?'),
          content: const Text(
              'Priority or Note is empty.\n\nSave anyway using defaults?\n• Priority: LOW\n• Note: "No remarks provided"'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save anyway')),
          ],
        ),
      ) ??
      false;
}

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final hasBlueprint = (_entry.blueprintImagePath != null) && File(_entry.blueprintImagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text('Tap to Tag — ${_entry.site}'),
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final boxSize = Size(box.maxWidth, box.maxHeight);

          // We'll draw the blueprint "contain" inside the available box.
          // For simplicity here we just use the whole area; InteractiveViewer will handle zoom/pan.
          _imgDrawnSize = boxSize;

          final blueprintChild = hasBlueprint
              ? Image.file(File(_entry.blueprintImagePath!), fit: BoxFit.contain)
              : Container(
                  color: const Color(0xFFF5F6FA),
                  alignment: Alignment.center,
                  child: const Text('Tap anywhere to add defects\n(Upload a blueprint on the Create page)\n\nPins will still work without a blueprint.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                );

          return Center(
            child: SizedBox(
              width: boxSize.width,
              height: boxSize.height,
              child: Stack(
                children: [
                  // Pan/zoom area
                  InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 8,
                    clipBehavior: Clip.none,
                    child: GestureDetector(
                      onTapUp: _onTapUp,
                      child: SizedBox(
                        width: boxSize.width,
                        height: boxSize.height,
                        child: blueprintChild,
                      ),
                    ),
                  ),

                  // Overlay pins
                  ..._pins.asMap().entries.map((e) {
                          final i = e.key;
                          final pin = e.value;
                          final dx = pin.nx * boxSize.width;
                          final dy = pin.ny * boxSize.height;

                          return Positioned(
                            left: dx - 16,
                            top: dy - 32,
                            child: GestureDetector(
                              onTap: () => _openPinSheet(i),
                              onLongPress: () => _onLongPressPin(i),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.location_on, size: 36, color: Colors.red),
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      pin.label,                           // <-- show custom label
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
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
