import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'create_page.dart';   // for ProjectEntry model
import 'details_page.dart';  // to open the operation screen

class EditDeletePage extends StatefulWidget {
  static const route = '/edit-delete';
  const EditDeletePage({super.key});

  @override
  State<EditDeletePage> createState() => _EditDeletePageState();
}

class _EditDeletePageState extends State<EditDeletePage> {
  final List<ProjectEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<File> _entriesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'data', 'projects.json'));
    await file.parent.create(recursive: true);
    return file;
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
      debugPrint('Load entries failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveEntries() async {
    try {
      final file = await _entriesFile();
      final jsonStr = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Save entries failed: $e');
    }
  }

  Future<void> _deleteProjectFolder(String id) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'data', 'projects', id));
      if (await dir.exists()) {
        await dir.delete(recursive: true); // delete tags/photos for this project
      }
    } catch (e) {
      debugPrint('Delete project folder failed: $e');
    }
  }

  Future<void> _confirmDelete(ProjectEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('This will remove "${entry.site} — ${entry.location}" '
            'from your list and delete its local defects/photos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _saveEntries();
    await _deleteProjectFolder(entry.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project deleted')),
    );
  }

  Future<void> _edit(ProjectEntry entry) async {
    // Open your existing Operation/Details page.
    await Navigator.pushNamed(context, DetailsPage.route, arguments: entry);

    // When returning, nothing to change in the list for now,
    // but you might want to refresh something if Details can update blueprint etc.
    // setState(() {}); // if you later allow editing core fields.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit / Delete'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No projects yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      title: Text(e.site, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(e.location),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _edit(e),
                            child: const Text('EDIT'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _confirmDelete(e),
                            child: const Text('DELETE'),
                          ),
                        ],
                      ),
                      onTap: () => _edit(e), // tap row also edits
                    );
                  },
                ),
    );
  }
}
