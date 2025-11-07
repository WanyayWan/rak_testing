import 'dart:convert';// lets u convert to/from JSON
import 'dart:io'; //give access to file and directory operation like creating, writing files
import 'dart:ui'; // for custom painting 
import 'package:flutter/material.dart'; // for materials like scaffold, appbar, buttons
import 'package:image_picker/image_picker.dart'; // allow app to capture images from camera or gallery
import 'package:path/path.dart' as p; // such as joining paths and extracting file names safely
import 'package:path_provider/path_provider.dart'; // lets u find safe directories on the devices for storing files
import 'package:flutter/painting.dart'; // for positioning and sizing images
import 'annotate_photo_page.dart';
import 'create_page.dart'; 



// ---------- Models (per-project) ----------

class Defect {
  final String photoPath;  
  final String severity;        
  final String defectType;     
  final String repairMethod;   
  final String note;

 Defect({
    required this.photoPath,
    required this.severity,
    required this.defectType,
    required this.repairMethod,
    required this.note,
  });
    Defect copyWith({
    String? photoPath,
    String? severity,
    String? defectType,
    String? repairMethod,
    String? note,
  }) {
    return Defect(
      photoPath: photoPath ?? this.photoPath,
      severity: severity ?? this.severity,
      defectType: defectType ?? this.defectType,
      repairMethod: repairMethod ?? this.repairMethod,
      note: note ?? this.note,
    );
  }


  Map<String, dynamic> toJson() => { // building a map for json encoding
    'photoPath': photoPath,
    'severity': severity,
    'defectType': defectType,
    'repairMethod': repairMethod,
    'note': note,
  };
//the keyword factory is used to define a special kind of constructor —
//one that can control what gets returned when you create an object.
  factory Defect.fromJson(Map<String, dynamic> m) => Defect( // takes a Json back to Defect object
    photoPath: (m['photoPath'] as String?) ?? '',
    severity:  (m['severity']  as String?) ?? '',
    defectType: (m['defectType'] as String?) ?? '',
    repairMethod: (m['repairMethod'] as String?) ?? '',
    note: (m['note'] as String?) ?? '',
  );
}

class ProjectMeta {
  final String location;     // required
  final DateTime date;       // required
  final String remarks;      // optional
  final String personInCharge;        // optional 

  ProjectMeta({required this.location, required this.date,  required this.remarks, this.personInCharge = ''});

  Map<String, dynamic> toJson() => {
        'location': location,
        'date': date.toIso8601String(),
        'remarks': remarks,
        'PIC': personInCharge,
      };
//the keyword factory is used to define a special kind of constructor —
//one that can control what gets returned when you create an object.
  factory ProjectMeta.fromJson(Map<String, dynamic> m) => ProjectMeta(
        location: (m['location'] as String?) ?? '',
        date: DateTime.tryParse((m['date'] as String?) ?? '') ?? DateTime.now(),
        remarks: (m['remarks'] as String?) ?? '',
        personInCharge: (m['PIC'] as String?) ?? '',
      );
}

class PinData {
  double nx; // 0..1
  double ny; // 0..1 
  //normalized x/y coordinates (from 0 to 1), meaning they are relative to the image size 
  //instead of pixel-based — so they scale correctly.
  String label; //a short tag for the label 
  final List<Defect> defects;

  PinData({required this.nx, required this.ny, required this.label, required this.defects});

  Map<String, dynamic> toJson() => {
        'nx': nx,
        'ny': ny,
        'label': label,
        'defects': defects.map((d) => d.toJson()).toList(),
      };
//the keyword factory is used to define a special kind of constructor —
//one that can control what gets returned when you create an object.
  factory PinData.fromJson(Map<String, dynamic> m) => PinData(
        nx: (m['nx'] as num).toDouble(),
        ny: (m['ny'] as num).toDouble(),
        label: (m['label'] as String?) ?? 'A?',
        defects: (m['defects'] as List? ?? [])
            .map((e) => Defect.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

const List<String> kSeverityOptions = <String>[
  'General View',
  'Safe',
  'Require Repair',
  'Unsafe',
  'Structural defect',
  'Non-structural defect',
];

const List<String> kDefectTypes = <String>[
  'Concrete Spalling with exposed rebar',
  'Concrete Spalling without exposed rebar',
  'Corroded steel member',
  'Rusted steel member',
  'Corroded fixings and brackets',
  'Plastering cracks',
  'Hollowness on plastering wall',
  'Peeled off plastering',
  'Chipped off plastering',
  'Dry stain mark',
  'Wet stain mark',
  'Damaged element',
  'Tilted element',
  'Dented element',
  'Misaligned element',
  'Missing element',
  'Deterioration of timber element',
  'Algae growth',
  'Peeled off/Blistering paint',
  'Plant growth',
  'Satisfactory',
];

const List<String> kRepairMethods = <String>[
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '7A',
  '7B',
  '8',
  '9',
  '10',
  '11',
  '12',
  '13',
  'NA',
];
//Offset _draggingOffset = Offset.zero; // To track the current dragging offset

// ---------- Page ----------

class DetailsPage extends StatefulWidget {
  static const route = '/details';
  const DetailsPage({super.key});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  bool _initialized = false; // this is to ensure didChangeDependencies runs only once and prevents redundant initializations
  late ProjectEntry _entry; // the main project object passed from previous page
  final _transform = TransformationController();  //interactiveViewer controller for zoom and pan
  final _personInChargeCtrl = TextEditingController(); // text controller for person in charge field
  final _metaFormKey = GlobalKey<FormState>(); // that identifies the form for validation
  final _locCtrl = TextEditingController(); //  text controller for location field
  final _remarksCtrl = TextEditingController();   // text controller for remarks field
  final _pinStackKey = GlobalKey();
  DateTime? _date; // required

 // Size? _imgDrawnSize; // the size the blueprint is drawn at (for tap mapping)
  Size? _imagePixels;       // intrinsic image size
  //Size? _fittedSize;        // actual drawn image size after BoxFit.contain in other words scaling down to fit the display
  // Offset _fittedTopLeft = Offset.zero; // top-left offset of the drawn imag   
  final List<PinData> _pins = []; 

  //late final Future<Directory> _projDirFuture;

  @override                    
  void dispose() {
    _locCtrl.dispose();
    _remarksCtrl.dispose();
    _personInChargeCtrl.dispose();
    super.dispose();
  }
  
  late String _locationId;
  //late String _locationName;
  late Future<Directory> _locationDirFuture;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_initialized) return;
  _initialized = true;
  

  final args = ModalRoute.of(context)!.settings.arguments;

  if (args is Map) {
    // from LocationPage
    _entry        = args['entry'] as ProjectEntry;
    _locationId   = (args['locationId'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString();
  //  _locationName = (args['locationName'] as String?) ?? 'Untitled';
  } else if (args is ProjectEntry) {
    // legacy path (if somewhere you still push just the entry)
    _entry        = args;
    _locationId   = 'default';
  //  _locationName = 'Default';
  } else {
    throw FlutterError('DetailsPage: missing or invalid arguments.');
  }

  _locationDirFuture = _ensureLocationDir(_entry.id, _locationId);
  Future.microtask(() async {
  await _loadBlueprintPathIntoEntry();
  await _ensureImagePixels();    // so BoxFit math knows the intrinsic size
  if (mounted) setState(() {});  // paint with the loaded path/size
});
  

  _loadPins();
  _loadMeta();
  _ensureImagePixels();
}

 Future<void> _editDefect(int pinIndex, int defectIndex) async {
  final d = _pins[pinIndex].defects[defectIndex];

  String? severity  = _coerceOrNull(d.severity, kSeverityOptions);
  String? defectType = _coerceOrNull(d.defectType, kDefectTypes);
  String? repairMethod = _coerceOrNull(d.repairMethod, kRepairMethods);
  final noteCtrl = TextEditingController(text: d.note);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final sysPad = MediaQuery.of(ctx).viewPadding;

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16,
              top: 16 + sysPad.top,
              bottom: 16 + sysPad.bottom + bottomInset,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Edit defect', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (File(d.photoPath).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(d.photoPath), height: 160, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.brush),
                    label: const Text('Re-annotate photo'),
                    onPressed: () async {
                      final String? savedPath = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnnotatePhotoPage(
                            imagePath: d.photoPath,
                            finalSavePath: d.photoPath, // overwrite same file
                          ),
                        ),
                      );
                      if (savedPath != null) {
                        setModal(() {});
                        await precacheImage(FileImage(File(savedPath)), context);
                      }
                    },
                  ),

                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: severity,
                    items: kSeverityOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setModal(() => severity = v),
                    decoration: const InputDecoration(
                      labelText: 'Severity', border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: defectType,
                    items: kDefectTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setModal(() => defectType = v),
                    decoration: const InputDecoration(
                      labelText: 'Defect type', border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: repairMethod,
                    items: kRepairMethods.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setModal(() => repairMethod = v),
                    decoration: const InputDecoration(
                      labelText: 'Repair method', border: OutlineInputBorder(),
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
                      final sv = (severity ?? 'General View');
                      final dt = (defectType ?? 'Damaged element');
                      final rm = (repairMethod ?? 'NA');
                      final n  = noteCtrl.text.trim().isEmpty
                          ? 'No remarks provided'
                          : noteCtrl.text.trim();

                      setState(() {
                        _pins[pinIndex].defects[defectIndex] = Defect(
                          photoPath: d.photoPath,
                          severity: sv,
                          defectType: dt,
                          repairMethod: rm,
                          note: n,
                        );
                      });
                      await _savePins();
                      if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
                    },
                    child: const Text('Save changes'),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  noteCtrl.dispose();
}

// Helper function — add this near bottom of class
String? _coerceOrNull(String? v, List<String> options) {
  if (v == null) return null;
  final t = v.trim();
  return options.contains(t) ? t : null;
}

 Future<Directory> _ensureLocationDir(String projectId, String locationId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'data', 'projects', projectId, 'locations', locationId));
    await dir.create(recursive: true);
    // also create photos subfolder up front
    await Directory(p.join(dir.path, 'photos')).create(recursive: true);
    return dir;
  }

  Future<File> _pinsFile() async {
    final dir = await _locationDirFuture;
    final f = File(p.join(dir.path, 'tags.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<File> _metaFile() async {
    final dir = await _locationDirFuture;
    final f = File(p.join(dir.path, 'project_meta.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<String?> _findExistingBlueprintPath() async {
  final dir = await _locationDirFuture;
  if (!await dir.exists()) return null;

  final exts = ['.png', '.jpg', '.jpeg', '.webp'];
  for (final f in await dir.list().toList()) {
    if (f is File) {
      final name = p.basename(f.path).toLowerCase();
      if (name.startsWith('blueprint') && exts.any((e) => name.endsWith(e))) {
        return f.path;
      }
    }
  }
  return null;
}

Future<void> _loadBlueprintPathIntoEntry() async {
  final bp = await _findExistingBlueprintPath();
  if (!mounted) return;
  setState(() {
    _entry = ProjectEntry(
      id: _entry.id,
      site: _entry.site,
      location: _entry.location,
      date: _entry.date,
      remarks: _entry.remarks,
      blueprintImagePath: bp,   // <- inject per-location blueprint
    );
  });
}


  Future<Directory> _photosDir() async {
    final dir = await _locationDirFuture;
    final photos = Directory(p.join(dir.path, 'photos'));
    await photos.create(recursive: true);
    return photos;
  }
  // ---------- Storage (per project) ----------
Future<void> _pickOrCaptureBlueprint() async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;

  final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
  if (picked == null) return;

  final locDir = await _locationDirFuture;

  // remove old blueprint.* so we keep exactly one file
  for (final f in await locDir.list().toList()) {
    if (f is File && p.basename(f.path).toLowerCase().startsWith('blueprint')) {
      await f.delete();
    }
  }

  final ext  = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
  final dest = File(p.join(locDir.path, 'blueprint$ext'));
  await dest.writeAsBytes(await File(picked.path).readAsBytes());

  if (!mounted) return;
  setState(() {
    _entry = ProjectEntry(
      id: _entry.id,
      site: _entry.site,
      location: _entry.location,
      date: _entry.date,
      remarks: _entry.remarks,
      blueprintImagePath: dest.path, 
    );
    _imagePixels = null;  // force re-read of intrinsic size
  });

  await _ensureImagePixels();     // read size
  if (!mounted) return;
  _transform.value = Matrix4.identity(); // center/fit
  setState(() {});                // Rebuild UI with new blueprint

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Blueprint added from ${source == ImageSource.camera ? "Camera" : "Gallery"}')),
  );
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
          _personInChargeCtrl.text = m.personInCharge;
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
    final meta = ProjectMeta
    (
      personInCharge: _personInChargeCtrl.text.trim(),
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
    
    Navigator.pop(context, _locCtrl.text.trim());
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


  Future<void> _savePins() async {
    try {
      final f = await _pinsFile();
      final jsonStr = jsonEncode(_pins.map((p) => p.toJson()).toList());
      await f.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Save pins failed: $e');
    }

  }

  Future<void> _ensureImagePixels() async {
  final path = _entry.blueprintImagePath;
  if (path == null || !File(path).existsSync()) return;
  if (_imagePixels != null) return;

  final bytes = await File(path).readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  _imagePixels = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
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

 /* Offset _toScene(Offset viewportPoint) {
  final inv = Matrix4.inverted(_transform.value);
  final scene = MatrixUtils.transformPoint(inv, viewportPoint);
  return scene;
}
*/

/* void _onTapUp(TapUpDetails d) async {
  if (_fittedSize == null) return;

  final scenePt = _toScene(d.localPosition);

  final inside = Rect.fromLTWH(
    _fittedTopLeft.dx, _fittedTopLeft.dy, _fittedSize!.width, _fittedSize!.height,
  );
  if (!inside.contains(scenePt)) return;

  final localInImage = scenePt - _fittedTopLeft;
  final nx = (localInImage.dx / _fittedSize!.width ).clamp(0.0, 1.0);
  final ny = (localInImage.dy / _fittedSize!.height).clamp(0.0, 1.0);

  final tempPin = PinData(nx: nx, ny: ny, label: _nextLabel(), defects: []);
  setState(() => _pins.add(tempPin));

  final defect = await _captureAndAnnotateDefect();
  if (!mounted) return;

  if (defect == null) {
    setState(() => _pins.remove(tempPin));
    return;
  }

  setState(() => tempPin.defects.add(defect));
  await _savePins();
} */

  /*Future<void> _onLongPressPin(int index) async {
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
  }  */

  // Tapping a pin opens its defect list (bottom sheet) with add/delete
  void _openPinSheet(int index) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) {
      final pin = _pins[index];
      return StatefulBuilder(builder: (ctx, setModal) {
        final sys = MediaQuery.of(ctx).viewPadding;
        final kb  = MediaQuery.of(ctx).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16 + sys.top,            // avoid status bar / cutouts
            bottom: 16 + sys.bottom + kb, // avoid gesture bar + keyboard
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Header row: title + actions ----
              Row(
                children: [
                  Text(
                    'Pin ${_pins[index].label}  •  Defects: ${pin.defects.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),

                  // Rename pin
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

                  // Add defect
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

                  // Delete pin
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete pin',
                    onPressed: () async {
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
                      if (ok == true) {
                        setState(() => _pins.removeAt(index));
                        await _savePins();
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop(); // close the bottom sheet
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pin deleted'))
                        );
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ---- Defect list ----
              ...pin.defects.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value;

                return Card(
                  child: ListTile(
                    leading: File(d.photoPath).existsSync()
                        ? Image.file(File(d.photoPath), width: 48, height: 48, fit: BoxFit.cover)
                        : const Icon(Icons.broken_image),
                    title: Text(d.severity),
                    subtitle: Text(
                      [
                        if (d.defectType.isNotEmpty) 'Type: ${d.defectType}',
                        if (d.repairMethod.isNotEmpty) 'Repair: ${d.repairMethod}',
                        if (d.note.isNotEmpty) 'Note: ${d.note}',
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        // EDIT defect
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            await _editDefect(index, i); // opens editor bottom sheet
                            setModal(() {});             // refresh this sheet after returning
                          },
                        ),
                        // DELETE defect
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () async {
                            setState(() => _pins[index].defects.removeAt(i));
                            setModal(() {});
                            await _savePins();
                          },
                        ),
                      ],
                    ),

                    // Tap also opens the editor
                    onTap: () async {
                      await _editDefect(index, i);
                      setModal(() {});
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

    // NEW
      // 3) annotate — write ONCE directly to final destination
      final photosDir = await _photosDir();
      final filename  = 'ann_${DateTime.now().millisecondsSinceEpoch}.png';
      final absPath   = p.join(photosDir.path, filename);

      final String? savedPath = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnotatePhotoPage(
            imagePath: picked.path,
            finalSavePath: absPath, // single write; no temp→copy
          ),
        ),
      );
      if (savedPath == null) return null;

// (optional) precache to remove first-frame decode hitch
await precacheImage(FileImage(File(savedPath)), context);


    // 5) collect priority + note (with confirmation + defaults)
    final result = await showModalBottomSheet<Map<String, String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetCtx) {
    final noteCtrl = TextEditingController();
    String? severity;
    String? defectType;
    String? repairMethod;

    return StatefulBuilder(
      builder: (ctx, setModalState) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final sysPad = MediaQuery.of(ctx).viewPadding; // safe padding for bars

        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16 + sysPad.top, bottom: 16 + bottomInset + sysPad.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Defect details', style: TextStyle(fontWeight: FontWeight.bold)),

                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  items: kSeverityOptions.map((s) =>
                    DropdownMenuItem(value: s, child: Text(s))
                  ).toList(),
                  onChanged: (v) => setModalState(() => severity = v),
                  decoration: const InputDecoration(
                    labelText: 'Severity', border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: defectType,
                  items: kDefectTypes.map((s) =>
                    DropdownMenuItem(value: s, child: Text(s))
                  ).toList(),
                  onChanged: (v) => setModalState(() => defectType = v),
                  decoration: const InputDecoration(
                    labelText: 'Defect type', border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: repairMethod,
                  items: kRepairMethods.map((s) =>
                    DropdownMenuItem(value: s, child: Text(s))
                  ).toList(),
                  onChanged: (v) => setModalState(() => repairMethod = v),
                  decoration: const InputDecoration(
                    labelText: 'Repair method', border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  minLines: 1, maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)', border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    // Graceful defaults if user leaves fields empty
                    String sv = (severity ?? '').trim();
                    String dt = (defectType ?? '').trim();
                    String rm = (repairMethod ?? '').trim();
                    String n  = noteCtrl.text.trim();

                    // If any of the 3 dropdowns are empty -> confirm + set defaults
                    if (sv.isEmpty || dt.isEmpty || rm.isEmpty) {
                      final ok = await _confirmSaveWithDefaults();
                      if (!ok) return;
                      if (sv.isEmpty) sv = 'General View';
                      if (dt.isEmpty) dt = 'Other';
                      if (rm.isEmpty) rm = 'NA';
                    }
                    if (n.isEmpty) n = 'No remarks provided';

                    Navigator.pop(sheetCtx, {
                      'severity': sv,
                      'defectType': dt,
                      'repairMethod': rm,
                      'note': n,
                    });
                  },
                  child: const Text('SAVE'),
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);
if (result == null) return null;

        return Defect(
      photoPath: absPath,
      severity: result['severity'] ?? 'General View',
      defectType: result['defectType'] ?? 'Damaged element',
      repairMethod: result['repairMethod'] ?? 'NA',
      note: (result['note']?.trim().isEmpty ?? true) ? 'No remarks provided' : result['note']!.trim(),
    ) ;
  }

Future<bool> _confirmSaveWithDefaults() async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Save with defaults?'),
          content: const Text(
              'You haven\'t provided all required fields.\n\nSave anyway using defaults?\n•'),
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
    final hasBlueprint = (_entry.blueprintImagePath?.isNotEmpty ?? false)
    && File(_entry.blueprintImagePath!).existsSync();


    return Scaffold(
          appBar: AppBar(
      title: Text('Tap to Tag — ${_entry.site}'),
      actions: [
       /* IconButton(
          tooltip: _entry.blueprintImagePath == null ? 'Add blueprint' : 'Replace blueprint',
          icon: const Icon(Icons.image_outlined),
          onPressed: _pickOrCaptureBlueprint,
        ), */
      ],
    ),
     body: SafeArea(           
      top: true,
      bottom: true,
      left: true,
      right: true,
      child: LayoutBuilder(
        builder: (context, box) {
      //    final boxSize = Size(box.maxWidth, box.maxHeight);
          // Compute drawn image size for BoxFit.contain
         /* if (_imagePixels != null) {
            final fitted = applyBoxFit(BoxFit.contain, _imagePixels!, boxSize);
            _fittedSize = fitted.destination;
            _fittedTopLeft = Offset(
              (boxSize.width  - _fittedSize!.width ) / 2.0,
              (boxSize.height - _fittedSize!.height) / 2.0,
            );
          } else {
            _fittedSize = null;
          //_fittedTopLeft = Offset.zero;
          } */

    //      final dateLabel = _date == null
         //   ? 'Select date'
          //  : '${_date!.day}/${_date!.month}/${_date!.year}';

          // We'll draw the blueprint "contain" inside the available box.
          // For simplicity here we just use the whole area; InteractiveViewer will handle zoom/pan.
     final blueprintChild = hasBlueprint
            ? Image.file(
                File(_entry.blueprintImagePath!),
                key: ValueKey(_entry.blueprintImagePath ?? DateTime.now().millisecondsSinceEpoch), // Use a unique key based on time to force rebuild
                fit: BoxFit.contain,
              )
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
    // ---- Blueprint + Pins area ON TOP ----
    Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final hasImageSize = _imagePixels != null && hasBlueprint;
          Size drawnSize;
          if (hasImageSize) {
            final fitted = applyBoxFit(BoxFit.contain, _imagePixels!, viewportSize);
            drawnSize = fitted.destination;
          } else {
            drawnSize = viewportSize;
          }

          final imgW = drawnSize.width;
          final imgH = drawnSize.height;

          return SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFFEEF1F6),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 8,
                    constrained: true,
                    boundaryMargin: EdgeInsets.zero,
                    clipBehavior: Clip.hardEdge,
                    child: Center(
                      child: SizedBox(
                        width: imgW,
                        height: imgH,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) async {
                            final local = d.localPosition;
                            if (local.dx < 0 || local.dy < 0 || local.dx > imgW || local.dy > imgH) return;

                            final nx = (local.dx / imgW).clamp(0.0, 1.0);
                            final ny = (local.dy / imgH).clamp(0.0, 1.0);

                            final tempPin = PinData(nx: nx, ny: ny, label: _nextLabel(), defects: []);
                            setState(() => _pins.add(tempPin));

                            final defect = await _captureAndAnnotateDefect();
                            if (!mounted) return;
                            if (defect == null) {
                              setState(() => _pins.remove(tempPin));
                              return;
                            }
                            setState(() => tempPin.defects.add(defect));
                            await _savePins();
                          },
                          child: Stack(
                            key: _pinStackKey,
                            children: [
                              if (hasBlueprint)
                                Image.file(
                                  File(_entry.blueprintImagePath!),
                                  key: ValueKey(_entry.blueprintImagePath),
                                  fit: BoxFit.contain,
                                  width: imgW,
                                  height: imgH,
                                )
                              else
                                Container(
                                  width: imgW,
                                  height: imgH,
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
                                ),

                              ..._pins.asMap().entries.map((e) {
                                  final i = e.key;
                                  final pin = e.value;
                                  final px = pin.nx * imgW;
                                  final py = pin.ny * imgH;

                                  return Positioned(
                                        left: px - 16,
                                        top: py - 32,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTap: () => _openPinSheet(i),

                                          // Optional: keep long-press inert so it never triggers deletion logic
                                          onLongPress: () {},

                                          onPanUpdate: (details) {
                                            // Convert finger coords to the Stack’s local space (fixed frame)
                                            final box = _pinStackKey.currentContext?.findRenderObject() as RenderBox?;
                                            if (box == null) return;

                                            final local = box.globalToLocal(details.globalPosition);

                                            // Clamp to the drawn image area (Stack is imgW x imgH)
                                            final clampedX = local.dx.clamp(0.0, imgW);
                                            final clampedY = local.dy.clamp(0.0, imgH);

                                            setState(() {
                                              _pins[i].nx = (clampedX / imgW).toDouble();
                                              _pins[i].ny = (clampedY / imgH).toDouble();
                                            });
                                          },

                                          onPanEnd: (_) async {
                                            // Don’t recompute from _draggingOffset—just persist
                                            await _savePins();
                                          },

                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              const Icon(Icons.location_on, size: 36, color: Colors.red),
                                              // ... label chip
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
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),

    // ---- Project Details form BELOW ----
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
              const SizedBox(height: 8),

              const Text('Person in Charge', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _personInChargeCtrl,
                decoration: const InputDecoration(
                  isDense: true, // <-- make compact
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Color(0xFFEDEFF2),
                  border: OutlineInputBorder(),
                  hintText: 'Enter full name',
                ),
              ),
              const SizedBox(height: 8),

              const Text('Location', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _locCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Location is required' : null,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Color(0xFFEDEFF2),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              const Text('Date', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
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
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: Color(0xFFEDEFF2),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _date == null
                        ? 'Select date'
                        : '${_date!.day}/${_date!.month}/${_date!.year}',
                  ),
                ),
              ),
              const SizedBox(height: 8),

              const Text('Remarks (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _remarksCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Color(0xFFEDEFF2),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Details'),
                  onPressed: _saveMeta,
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
  ],
);

        },
      ),
      ),
              
    );
  }
}
