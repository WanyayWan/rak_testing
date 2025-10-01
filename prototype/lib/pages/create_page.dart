// lib/pages/create_page.dart
import 'dart:convert'; // <-- added (for JSON)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'details_page.dart';

class ProjectEntry {
  String id;
  String site;
  String location;
  DateTime? date;
  String remarks;
  String? blueprintImagePath; // stored under app docs dir

  ProjectEntry({
    required this.id,
    required this.site,
    required this.location,
    required this.date,
    required this.remarks,
    this.blueprintImagePath,
  });

  // ---- JSON helpers ----
  Map<String, dynamic> toJson() => {
        'id': id,
        'site': site,
        'location': location,
        'date': date?.toIso8601String(),
        'remarks': remarks,
        'blueprintImagePath': blueprintImagePath,
      };

  factory ProjectEntry.fromJson(Map<String, dynamic> m) => ProjectEntry(
        id: (m['id'] as String?) ?? '',
        site: (m['site'] as String?) ?? '',
        location: (m['location'] as String?) ?? '',
        date: (m['date'] as String?) != null ? DateTime.tryParse(m['date'] as String) : null,
        remarks: (m['remarks'] as String?) ?? '',
        blueprintImagePath: m['blueprintImagePath'] as String?,
      );
}

class CreatePage extends StatefulWidget {
  static const route = '/create';
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _siteCtrl = TextEditingController();
  String? _blueprintPath; // copied file path under app docs

  final List<ProjectEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries(); // <-- load JSON on startup
  }

  @override
  void dispose() {
    _siteCtrl.dispose();
    super.dispose();
  }

  // ---------- Date & Image picking ----------
 /* Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => _date = d);
  } */

  Future<void> _pickBlueprintImage() async {
    // 1) Ask user: Camera or Gallery
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

    // 2) Pick/take the image
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null) return;

    // 3) Copy into app documents so the app owns the file lifecycle
    final docs = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(docs.path, 'blueprints'));
    await destDir.create(recursive: true);
    final filename = '${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
    final destPath = p.join(destDir.path, filename);
    await File(picked.path).copy(destPath);

    // 4) Update UI
    if (!mounted) return;
    setState(() => _blueprintPath = destPath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Blueprint added from ${source == ImageSource.camera ? "Camera" : "Gallery"}')),
    );
  }

  // ---------- JSON persistence ----------
  Future<File> _entriesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'data', 'projects.json'));
    await file.parent.create(recursive: true);
    return file;
  }

  Future<void> _saveEntries() async {
    try {
      final file = await _entriesFile();
      final jsonStr = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Save failed: $e');
    }
  }

  Future<void> _loadEntries() async {
    try {
      final file = await _entriesFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        setState(() {
          _entries
            ..clear()
            ..addAll(list.map((e) => ProjectEntry.fromJson((e as Map).cast<String, dynamic>())));
        });
      }
    } catch (e) {
      debugPrint('Load failed: $e');
    }
  }

  // ---------- Actions ----------
  Future<void> _onNext() async {
    // Even if no blueprint picked, we allow proceeding.
    if (!_formKey.currentState!.validate()) return;

    final entry = ProjectEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      site: _siteCtrl.text.trim(),
      location: '',          // moved to DetailsPage
      date: null,            // moved to DetailsPage
      remarks: '',           // moved to DetailsPage
      blueprintImagePath: _blueprintPath,
    );

    // Navigate to DetailsPage; allow editing there. When it returns with an updated entry, save it.
    final updated = await Navigator.pushNamed(
      context,
      DetailsPage.route,
      arguments: entry,
    ) as ProjectEntry?;

    final toSave = updated ?? entry;
    setState(() {
      _entries.add(toSave);
      // clear form for next input
      _siteCtrl.clear();
      _blueprintPath = null;
    });
    await _saveEntries(); // <-- persist after add
  }

  Future<void> _editEntry(ProjectEntry entry) async {
    final updated = await Navigator.pushNamed(
      context,
      DetailsPage.route,
      arguments: entry,
    ) as ProjectEntry?;
    if (updated == null) return;
    setState(() {
      final idx = _entries.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) _entries[idx] = updated;
    });
    await _saveEntries(); // <-- persist after edit
  }

  Future<void> _deleteEntry(ProjectEntry entry) async {
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _saveEntries(); // <-- persist after delete
  }

  Future<void> _exportAllToPdf() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No entries to export')));
      return;
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text('Project Export', style: pw.TextStyle(fontSize: 22))),
          pw.Table.fromTextArray(
            headers: ['Site', 'Location', 'Date', 'Remarks'],
            data: _entries.map((e) {
              final d = e.date != null ? '${e.date!.day}/${e.date!.month}/${e.date!.year}' : '-';
              return [e.site, e.location, d, e.remarks];
            }).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Blueprint Images', style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 8),
          for (final e in _entries)
            if (e.blueprintImagePath != null && File(e.blueprintImagePath!).existsSync())
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${e.site} — ${e.location}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 6),
                  pw.Image(pw.MemoryImage(File(e.blueprintImagePath!).readAsBytesSync()), height: 220),
                  pw.SizedBox(height: 14),
                ],
              ),
        ],
      ),
    );

    final docs = await getApplicationDocumentsDirectory();
    final outPath = p.join(docs.path, 'exports', 'project_export_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await Directory(p.dirname(outPath)).create(recursive: true);
    final outFile = File(outPath);
    await outFile.writeAsBytes(await doc.save());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported PDF to:\n$outPath')),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Page'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Site', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _siteCtrl,
                    decoration: const InputDecoration(
                      filled: true, fillColor: Color(0xFFEDEFF2),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter site' : null,
                  ),
                  const SizedBox(height: 14),

                /*    const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _locCtrl,
                      decoration: const InputDecoration(
                        filled: true, fillColor: Color(0xFFEDEFF2),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter location' : null,
                    ),
                    const SizedBox(height: 14),

                    const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          filled: true, fillColor: Color(0xFFEDEFF2),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(dateLabel),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Remarks', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _remarksCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        filled: true, fillColor: Color(0xFFEDEFF2),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
*/
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _pickBlueprintImage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('UPLOAD BLUEPRINT'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _exportAllToPdf,
                          child: const Text('EXPORT ALL'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _onNext,
                      child: const Text('Next'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            if (_entries.isNotEmpty)
              const Text('Saved entries', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            ..._entries.map((e) => Card(
                  elevation: 1,
                  child: ListTile(
                    title: Text(e.site),
                    subtitle: Text(e.location),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editEntry(e),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteEntry(e),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
