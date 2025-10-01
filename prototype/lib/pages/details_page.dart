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

class ProjectMeta {
  final String location;     // required
  final DateTime date;       // required
  final String remarks;      // optional

  ProjectMeta({required this.location, required this.date, required this.remarks});

  Map<String, dynamic> toJson() => {
        'location': location,
        'date': date.toIso8601String(),
        'remarks': remarks,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> m) => ProjectMeta(
        location: (m['location'] as String?) ?? '',
        date: DateTime.tryParse((m['date'] as String?) ?? '') ?? DateTime.now(),
        remarks: (m['remarks'] as String?) ?? '',
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

  final _metaFormKey = GlobalKey<FormState>();
  final _locCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  DateTime? _date; // required

  Size? _imgDrawnSize; // the size the blueprint is drawn at (for tap mapping)
  final List<PinData> _pins = [];

  late final Future<Directory> _projDirFuture;

  @override
  void dispose() {
    _locCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    
    super.didChangeDependencies();
    if (_initialized) return;               // <-- guard: run once
    _initialized = true;
    
    _entry = ModalRoute.of(context)!.settings.arguments as ProjectEntry;
    _projDirFuture = _ensureProjectDir(_entry.id);
 
    _loadPins();
    _loadMeta();
  }

  // ---------- Storage (per project) ----------
Future<void> _pickOrCaptureBlueprint() async {
  // Ask for source
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
    ),
  );
  if (source == null) return;

  // Pick / take photo
  final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
  if (picked == null) return;

  // Copy into this project's folder so we control its lifecycle
  final projDir = await _projDirFuture; // .../data/projects/<id>
  final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
  final dest = File(p.join(projDir.path, 'blueprint$ext'));
  await dest.writeAsBytes(await File(picked.path).readAsBytes());

  if (!mounted) return;

  // Update state so UI re-builds immediately
  setState(() {
    _entry.blueprintImagePath = dest.path;
  });

  // (Optional) keep projects.json in sync so lists show the thumbnail later
  try {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'data', 'projects.json'));
    if (await file.exists()) {
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      final entries = list
          .map((e) => ProjectEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final i = entries.indexWhere((e) => e.id == _entry.id);
      if (i >= 0) {
        entries[i] = ProjectEntry(
          id: entries[i].id,
          site: entries[i].site,
          location: entries[i].location,
          date: entries[i].date,
          remarks: entries[i].remarks,
          blueprintImagePath: dest.path,
        );
        await file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
      }
    }
  } catch (e) {
    debugPrint('sync blueprint path failed: $e');
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Blueprint added from ${source == ImageSource.camera ? "Camera" : "Gallery"}')),
  );
}

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
  Future<File> _metaFile() async {
  final dir = await _projDirFuture;
  final f = File(p.join(dir.path, 'project_meta.json'));
  await f.parent.create(recursive: true);
  return f;
}

  Future<void> _loadMeta() async {
    try {
      final f = await _metaFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final m = ProjectMeta.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
        if (!mounted) return;
        setState(() {
          _locCtrl.text = m.location;
          _date = m.date;
          _remarksCtrl.text = m.remarks;
        });
      } else {
        _date = null; // not set yet
      }
    } catch (e) {
      debugPrint('Load meta failed: $e');
    }
  }

  Future<void> _saveMeta() async {
    if (!_metaFormKey.currentState!.validate()) return;
    final meta = ProjectMeta(
      location: _locCtrl.text.trim(),
      date: _date!, // validated non-null
      remarks: _remarksCtrl.text.trim(),
    );

    try {
      final f = await _metaFile();
      await f.writeAsString(jsonEncode(meta.toJson()));
    } catch (e) {
      debugPrint('Save meta failed: $e');
    }

    await _syncMetaIntoProjectsJson(meta);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details saved')));
  }

  // Optional: keep projects.json in sync (for list displays)
  Future<void> _syncMetaIntoProjectsJson(ProjectMeta meta) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, 'data', 'projects.json'));
      if (!await file.exists()) return;

      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      final entries = list.map((e) => ProjectEntry.fromJson((e as Map).cast<String, dynamic>())).toList();

      final idx = entries.indexWhere((e) => e.id == _entry.id);
      if (idx >= 0) {
        entries[idx] = ProjectEntry(
          id: entries[idx].id,
          site: entries[idx].site,
          location: meta.location,
          date: meta.date,
          remarks: meta.remarks,
          blueprintImagePath: _entry.blueprintImagePath ?? entries[idx].blueprintImagePath,
        );
        await file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
      }
    } catch (e) {
      debugPrint('Sync meta to projects.json failed: $e');
    }
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

    // Save the chosen blueprint into this project's folder and update state + projects.json
  Future<void> _pickOrReplaceBlueprint() async {
    // 1) Ask source
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
    if (source == null) return;

    // 2) Pick/take photo
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (picked == null) return;

    // 3) Copy into *this project* folder (so it travels with the project)
    final dir = await _projDirFuture;
    final ext = p.extension(picked.path);
    final destPath = p.join(dir.path, 'blueprint$ext'); // overwrite same name
    await File(picked.path).copy(destPath);

    // 4) Update in-memory entry + persist to projects.json
    setState(() {
      _entry = ProjectEntry(
        id: _entry.id,
        site: _entry.site,
        location: _locCtrl.text.trim().isEmpty ? _entry.location : _locCtrl.text.trim(),
        date: _date ?? _entry.date,
        remarks: _remarksCtrl.text.trim().isEmpty ? _entry.remarks : _remarksCtrl.text.trim(),
        blueprintImagePath: destPath,
      );
    });
    await _syncBlueprintPathInProjectsJson(destPath);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Blueprint ${File(destPath).existsSync() ? "saved" : "updated"}')),
    );
  }

  // keep projects.json in sync with the new blueprint path
  Future<void> _syncBlueprintPathInProjectsJson(String absPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, 'data', 'projects.json'));
      if (!await file.exists()) return;

      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      final entries = list.map((e) => ProjectEntry.fromJson((e as Map).cast<String, dynamic>())).toList();

      final idx = entries.indexWhere((e) => e.id == _entry.id);
      if (idx >= 0) {
        entries[idx] = ProjectEntry(
          id: entries[idx].id,
          site: entries[idx].site,
          location: entries[idx].location,
          date: entries[idx].date,
          remarks: entries[idx].remarks,
          blueprintImagePath: absPath,
        );
        await file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
      }
    } catch (e) {
      debugPrint('Sync blueprint path failed: $e');
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
      useSafeArea: true,
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
  useSafeArea: true,
  builder: (sheetCtx) {
    // create once per sheet
    final noteCtrl = TextEditingController();
    String? priority;

    return StatefulBuilder(
      builder: (ctx, setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                  DropdownMenuItem(value: 'LOW',  child: Text('LOW PRIORITY')),
                  DropdownMenuItem(value: 'MED',  child: Text('MED PRIORITY')),
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH PRIORITY')),
                ],
                onChanged: (v) => setModalState(() => priority = v),
                decoration: const InputDecoration(
                  labelText: 'Priority', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: noteCtrl,
                minLines: 1, maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              FilledButton(
                onPressed: () async {
                  String? p = priority;
                  String n = noteCtrl.text.trim();

                  if (p == null || p.isEmpty || n.isEmpty) {
                    final ok = await _confirmSaveWithDefaults();
                    if (!ok) return;
                    p ??= 'LOW';
                    if (n.isEmpty) n = 'No remarks provided';
                  }

                  Navigator.pop(sheetCtx, {'priority': p!, 'note': n});
                },
                child: const Text('SAVE'),
              ),
            ],
          ),
        );
      },
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
      actions: [
        IconButton(
          tooltip: _entry.blueprintImagePath == null ? 'Add blueprint' : 'Replace blueprint',
          icon: const Icon(Icons.image_outlined),
          onPressed: _pickOrCaptureBlueprint,
        ),
      ],
    ),
      
      body: LayoutBuilder(
        builder: (context, box) {
          final boxSize = Size(box.maxWidth, box.maxHeight);

          final dateLabel = _date == null
            ? 'Select date'
            : '${_date!.day}/${_date!.month}/${_date!.year}';

          // We'll draw the blueprint "contain" inside the available box.
          // For simplicity here we just use the whole area; InteractiveViewer will handle zoom/pan.
          _imgDrawnSize = boxSize;

          final blueprintChild = hasBlueprint
                    ? Image.file(File(_entry.blueprintImagePath!), key: ValueKey(_entry.blueprintImagePath), // busts image cache on path change
                     fit: BoxFit.contain)
                    : Container(
                        color: const Color(0xFFF5F6FA),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No blueprint yet.\nYou can still place pins.\n\nAdd a blueprint for better context.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text('Add Blueprint'),
                              onPressed: _pickOrCaptureBlueprint,
                            ),
                          ],
                        ),
                      );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // [E] ---- Project Details form (Location / Date / Remarks) ----
              Card(
                elevation: 1,
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Form(
                    key: _metaFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Project Details', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),

                        const Text('Location', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _locCtrl,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Location is required' : null,
                          decoration: const InputDecoration(
                            filled: true, fillColor: Color(0xFFEDEFF2), border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        const Text('Date', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date ?? now,
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (picked != null) setState(() => _date = picked);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              filled: true, fillColor: Color(0xFFEDEFF2), border: OutlineInputBorder(),
                            ),
                            child: Text(dateLabel),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_date == null)
                          const Text('Date is required', style: TextStyle(color: Colors.red, fontSize: 12)),

                        const SizedBox(height: 12),
                        const Text('Remarks (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _remarksCtrl,
                          minLines: 1, maxLines: 3,
                          decoration: const InputDecoration(
                            filled: true, fillColor: Color(0xFFEDEFF2), border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Save Details'),
                            onPressed:  _saveMeta,
                            
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- Blueprint + Pins area (your existing code), now inside Expanded ----
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: boxSize.width,
                    height: boxSize.height,
                    child: Stack(
                      children: [
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
                                      pin.label,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
