// this page will come after the user clicks "Create" on HomePage
import 'dart:convert'; // for JSON encoding/decoding
import 'dart:io'; // for File and Directory operations
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p; // for path operations
import 'package:path_provider/path_provider.dart'; // to get app document directory
//import 'details_page.dart';
import 'location_page.dart';

class ProjectEntry { // model class for a project entry
  String id;
  String site;
  String location;
  DateTime? date;
  String remarks;
  String? blueprintImagePath; // stored under app docs dir

  ProjectEntry({  // constructor, required means it must be provided when creating an instance
    required this.id,
    required this.site,
    required this.location,
    required this.date,
    required this.remarks,
    this.blueprintImagePath, //  if we remove the required keyword this can be null
  });

  // ---- JSON helpers ----
  Map<String, dynamic> toJson() => {    //this method is for turning the object into a map that can be easily converted to JSON format 
                                        //in other words turning the object into a format that can be easily stored or transmitted
        'id': id,
        'site': site,
        'location': location,
        'date': date?.toIso8601String(),
        'remarks': remarks,
        'blueprintImagePath': blueprintImagePath,
      };
// Turning the text back into an object
  factory ProjectEntry.fromJson(Map<String, dynamic> m) => ProjectEntry(  
        id: (m['id'] as String?) ?? '', // ?? '' means if the value is missing, it will default to an empty string
        site: (m['site'] as String?) ?? '',
        location: (m['location'] as String?) ?? '',
        date: (m['date'] as String?) != null ? DateTime.tryParse(m['date'] as String) : null,
        remarks: (m['remarks'] as String?) ?? '',
        blueprintImagePath: m['blueprintImagePath'] as String?,
      );
}

class CreatePage extends StatefulWidget {   // stateful because we need to manage form state and image picking
  static const route = '/create';   // route name for navigation
  const CreatePage({super.key}); // constructor

  @override
  State<CreatePage> createState() => _CreatePageState(); 
  // every stateful widget must have a state class and must override the createState method to return an instance of that state class
}

class _CreatePageState extends State<CreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _siteCtrl = TextEditingController();  // controller for site input
  // it lets u control and access the text in the text field like read and write
  String? _blueprintPath; // copied file path under app docs

  final List<ProjectEntry> _entries = [];

  @override
  void initState() {    // initizating
    super.initState();
    _loadEntries(); // <-- load JSON on startup
  }

  @override
  void dispose() {
    _siteCtrl.dispose();  //frees resources used by the text controller to avoid memory leaks 
                          // lets say if we go back and forth between pages without disposing the controller it will keep consuming memory
    super.dispose();
  }

  // ---------- JSON persistence ----------
  Future<File> _entriesFile() async {
    final dir = await getApplicationDocumentsDirectory();  // this is where your app can store files it will be different according to the platform 
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
      final file = await _entriesFile();  // 
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
      LocationPage.route,
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
  await Navigator.pushNamed(
    context,
    LocationPage.route,
    arguments: entry,
  );


}

  Future<void> _deleteEntry(ProjectEntry entry) async {
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _saveEntries(); // <-- persist after delete
  }

  /*Future<void> _exportAllToPdf() async {
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
  }*/

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create A Project'),
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
