// lib/pages/location_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'create_page.dart';   // for ProjectEntry
import 'details_page.dart';  // we will pass project + location info

class LocationLabel {
  final String id;     // unique per location (string timestamp)
  final String name;   // user-entered name (e.g., "Level 1 - Room A")

  LocationLabel({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory LocationLabel.fromJson(Map<String, dynamic> m) =>
      LocationLabel(id: (m['id'] as String?) ?? '', name: (m['name'] as String?) ?? '');
}

class LocationPage extends StatefulWidget {
  static const route = '/locations';
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  late final ProjectEntry _entry;
  bool _initialized = false;

  final List<LocationLabel> _locations = [];
  late Future<Directory> _projectDirFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _entry = ModalRoute.of(context)!.settings.arguments as ProjectEntry;
    _projectDirFuture = _ensureProjectDir(_entry.id);
    _loadLocations();
  }

  Future<Directory> _ensureProjectDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'data', 'projects', id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _locationsFile() async {
    final dir = await _projectDirFuture;
    final f = File(p.join(dir.path, 'locations.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<void> _loadLocations() async {
    try {
      final f = await _locationsFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        setState(() {
          _locations
            ..clear()
            ..addAll(list.map((e) => LocationLabel.fromJson((e as Map).cast<String, dynamic>())));
        });
      }
    } catch (e) {
      debugPrint('Load locations failed: $e');
    }
  }

  Future<void> _saveLocations() async {
    try {
      final f = await _locationsFile();
      await f.writeAsString(jsonEncode(_locations.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Save locations failed: $e');
    }
  }

  Future<void> _renameLocation(LocationLabel loc) async {
  final ctrl = TextEditingController(text: loc.name);
  final newName = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Rename location'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          labelText: 'Location name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
      ],
    ),
  );

  if (newName == null || newName.isEmpty) return;
  final idx = _locations.indexWhere((e) => e.id == loc.id);
  if (idx < 0) return;
  setState(() => _locations[idx] = LocationLabel(id: loc.id, name: newName));
  await _saveLocations();
}

void _openLocation(LocationLabel loc) {
  Navigator.pushNamed(
    context,
    DetailsPage.route,
    arguments: {
      'entry': _entry,
      'locationId': loc.id,
      'locationName': loc.name,
    },
  );
}
Future<void> _addLocation() async {
  if (!mounted) return;
  Navigator.pushNamed(
    context,
    DetailsPage.route,
    arguments: {'entry': _entry},
  ).then((_) => _loadLocations());
}

  Future<void> _deleteLocation(LocationLabel loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this location?'),
        content: Text('This removes the label from the list. '
            'Existing files under this location folder are not automatically deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _locations.removeWhere((e) => e.id == loc.id));
    await _saveLocations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Locations — ${_entry.site}'),
      ),
      body: SafeArea(
        child: _locations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No locations yet.\nTap the + button to add your first level/room.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _locations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final loc = _locations[i];
                  return Card(
                    child: ListTile(
                      title: Text(loc.name),
                      subtitle: Text('ID: ${loc.id}'),
                      onTap: () => _openLocation(loc),
                      trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _renameLocation(loc),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _deleteLocation(loc),
                              ),
                            ],
                          ),

                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
  onPressed: () async {
    final result = await Navigator.pushNamed(
      context,
      DetailsPage.route,
      arguments: { 'entry': _entry }, // just the project; new location is created after save
    );

    // If DetailsPage popped with a non-empty location name, create a new list item
    if (result is String && result.trim().isNotEmpty) {
      final loc = LocationLabel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result.trim(),
      );
      setState(() => _locations.add(loc));
      await _saveLocations();
    }
  },
  icon: const Icon(Icons.add),
  label: const Text('Create new label'),
),
    );
  }
}
