// lib/pages/location_page.dart
// Manages the list of "locations" for a single project (e.g., floors/rooms)


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

  // JSON serialization
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  //the keyword factory is used to define a special kind of constructor —
  //one that can control what gets returned when you create an object.
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

  final List<LocationLabel> _locations = []; // in-memory list for UI
  // later this list will be used to save/load from disk and display
  late Future<Directory> _projectDirFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    //ProjectEntry passed via Navigator
    _entry = ModalRoute.of(context)!.settings.arguments as ProjectEntry;

    // Ensure project directory exists
    _projectDirFuture = _ensureProjectDir(_entry.id);

    // Load existing locations
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
/*
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

  final i = _locations.indexWhere((e) => e.id == loc.id);
  if (i < 0) return;
  setState(() => _locations[i] = LocationLabel(id: loc.id, name: newName));
  await _saveLocations();
}  */

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
  // create a new empty location id
  final newId = DateTime.now().millisecondsSinceEpoch.toString();

  // ensure the folder exists so DetailsPage can save files immediately
  final docs = await getApplicationDocumentsDirectory();
  final locDir = Directory(p.join(docs.path, 'data', 'projects', _entry.id, 'locations', newId));
  await locDir.create(recursive: true);
  await Directory(p.join(locDir.path, 'photos')).create(recursive: true);

  // go to details to enter the name there; expect a String name on pop
  final result = await Navigator.pushNamed(
    
    context,
    DetailsPage.route,
    arguments: {
      'entry': _entry,
      'locationId': newId,
      'locationName': '', // empty; user will enter in DetailsPage
    },
  );

  if (result is String && result.trim().isNotEmpty) {
    final loc = LocationLabel(id: newId, name: result.trim());
    setState(() => _locations.add(loc));
    await _saveLocations();
  } else {
    // user backed out without saving ->  clean up the empty folder
    if (await locDir.exists()) {
      try { await locDir.delete(recursive: true); } catch (_) {}
    }
  }
}

  Future<void> _deleteLocation(LocationLabel loc) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete this location?'),
      content: Text('This will delete all files for this location (blueprint, pins, photos).'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true) return;

  // Remove folder
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'data', 'projects', _entry.id, 'locations', loc.id));
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }

  // Update list
  setState(() => _locations.removeWhere((e) => e.id == loc.id));
  await _saveLocations();
}
// Edit a location by navigating to DetailsPage and accepting an updated name on return
Future<void> _editLocation(LocationLabel loc) async {
  final result = await Navigator.pushNamed(
    context,
    DetailsPage.route,
    arguments: {
      'entry': _entry,
      'locationId': loc.id,
      'locationName': loc.name,
    },
  );

  if (result is String && result.trim().isNotEmpty) {
    final i = _locations.indexWhere((e) => e.id == loc.id);
    if (i >= 0) {
      setState(() => _locations[i] = LocationLabel(id: loc.id, name: result.trim()));
      await _saveLocations();
    }
  }
}
  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    return Scaffold
    (
      appBar: AppBar
      (
        title: Text(' ${_entry.site}'),
      ),
      body: SafeArea
      (
        // Showing message for no locations
        child: _locations.isEmpty
            ? Center
            (
                child: Padding
                (
                  padding: const EdgeInsets.all(24),
                  child: Text
                  (
                    'No locations yet.\nTap the + button to add your first level/room.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
            )
            // If locations exist, show them in a list
            : ListView.separated
            (
                padding: const EdgeInsets.all(12),
                itemCount: _locations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6), //adding a space between cards
                //_ means we are ignoring the context parameter
                itemBuilder: (_, i) 
                {
                final loc = _locations[i];
                  return Card
                  (
                    child: ListTile(
                    title: Text(loc.name),
                 //   subtitle: Text('ID: ${loc.id}'),
                    onTap: () => _openLocation(loc),
                    trailing: Row
                          (
                            mainAxisSize: MainAxisSize.min,
                            children: 
                            [                       
                            IconButton
                              (
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

  //Floating action button to add a new location
      floatingActionButton: FloatingActionButton.extended
      (
          onPressed: _addLocation,            // <-- just call your helper
          icon: const Icon(Icons.add),
          label: const Text('Create Defect Locations'),
      ),

    );
  }
}
