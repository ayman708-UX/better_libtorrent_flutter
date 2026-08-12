import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:better_libtorrent_flutter/torrent_engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Libtorrent Flutter Example',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const TorrentScreen(),
    );
  }
}

class TorrentScreen extends StatefulWidget {
  const TorrentScreen({super.key});

  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
  TorrentSession? _session;
  final TextEditingController _magnetController = TextEditingController(
    text: 'magnet:?xt=urn:btih:3b245504cf5f11bbdbe1201cea6a6bf45aee1bc0&dn=ubuntu-24.04-desktop-amd64.iso',
  );

  final List<TorrentHandle> _handles = [];
  final Map<int, TorrentStatus> _statuses = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      _session = await TorrentSession.create();
      _session!.alerts.listen((alert) {
        if (alert is TorrentStateUpdate) {
          setState(() {
            for (var status in alert.status) {
              _statuses[status.id] = status;
            }
          });
        }
      });
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing torrent engine: $e');
    }
  }

  Future<void> _addMagnet() async {
    if (_session == null) return;
    
    final uri = _magnetController.text.trim();
    if (uri.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final savePath = Directory('${dir.path}/Torrents');
    if (!await savePath.exists()) {
      await savePath.create(recursive: true);
    }

    try {
      final handle = await _session!.addMagnet(uri, savePath: savePath.path);
      if (mounted) {
        setState(() {
          _handles.add(handle);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Magnet added!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding magnet: $e')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _getStateString(int state) {
    switch (state) {
      case 1: return 'Checking Files';
      case 2: return 'Downloading Metadata';
      case 3: return 'Downloading';
      case 4: return 'Finished';
      case 5: return 'Seeding';
      case 6: return 'Allocating';
      case 7: return 'Checking Resume Data';
      default: return 'Unknown ($state)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Libtorrent Engine'),
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: () => _session!.pause(),
              tooltip: 'Pause Session',
            ),
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => _session!.resume(),
              tooltip: 'Resume Session',
            ),
        ],
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _magnetController,
                          decoration: const InputDecoration(
                            labelText: 'Magnet URI',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _addMagnet,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _handles.isEmpty
                      ? const Center(child: Text('No torrents added yet.'))
                      : ListView.builder(
                          itemCount: _handles.length,
                          itemBuilder: (context, index) {
                            // Find status by matching index, assuming simple mapping for example
                            // Note: Realistically we need the handle ID, but we didn't expose it directly 
                            // on TorrentHandle in the dart wrapper. Let's just grab the first status if 1 item.
                            // To be perfect, we should expose `id` on TorrentHandle, but for the example we can map 
                            // by assuming keys order or we'll just show all statuses.
                            
                            // Let's just list all statuses instead of mapping to _handles directly 
                            // since the status gives us the real id.
                            final statusList = _statuses.values.toList();
                            if (index >= statusList.length) return const SizedBox.shrink();
                            
                            final status = statusList[index];
                            final progress = (status.progress * 100).toStringAsFixed(1);
                            
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Torrent ID: ${status.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 8),
                                    Text('State: ${_getStateString(status.state)}'),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(value: status.progress),
                                    const SizedBox(height: 4),
                                    Text('Progress: $progress% (${_formatBytes(status.totalDone)} / ${_formatBytes(status.totalWanted)})'),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('↓ ${_formatBytes(status.downloadRate)}/s'),
                                        Text('↑ ${_formatBytes(status.uploadRate)}/s'),
                                        Text('Peers: ${status.numPeers} (${status.numSeeds} seeds)'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }
}
