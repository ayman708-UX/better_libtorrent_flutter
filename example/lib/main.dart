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
        cardTheme: const CardThemeData(
          color: Color(0xFF2A2A3C),
          elevation: 2,
        ),
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
  String? _initError;

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
        } else if (alert is MetadataReceivedAlert) {
          // Metadata arrived for a magnet — refresh UI to show name + files
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Metadata received!')),
            );
          }
        } else if (alert is TorrentFinishedAlert) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download complete!')),
            );
          }
        } else if (alert is TorrentErrorAlert) {
          debugPrint('Torrent error: ${alert.error}');
        }
      });
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing torrent engine: $e');
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
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
      final handle = _session!.addMagnet(uri, savePath: savePath.path);
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
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showFiles(TorrentHandle handle) {
    final files = handle.getFiles();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No metadata yet — waiting for peers...')),
      );
      return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A3C),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: files.length,
                  itemBuilder: (ctx, index) {
                    final file = files[index];
                    return ListTile(
                      leading: Icon(_getFileIcon(file.name), color: Colors.blueAccent),
                      title: Text(file.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_formatBytes(file.size)),
                      trailing: PopupMenuButton<int>(
                        onSelected: (priority) {
                          handle.setFilePriority(file.index, priority);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Set "${file.name}" priority to $priority')),
                          );
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 0, child: Text('Skip (0)')),
                          const PopupMenuItem(value: 1, child: Text('Low (1)')),
                          const PopupMenuItem(value: 4, child: Text('Normal (4)')),
                          const PopupMenuItem(value: 7, child: Text('Highest (7)')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': case 'mkv': case 'avi': case 'mov': case 'wmv': case 'flv': case 'webm':
        return Icons.movie;
      case 'mp3': case 'flac': case 'wav': case 'aac': case 'ogg':
        return Icons.music_note;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'bmp': case 'webp':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return Icons.archive;
      case 'iso':
        return Icons.album;
      case 'txt': case 'nfo': case 'md':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _estimateEta(TorrentStatus status) {
    if (status.downloadRate <= 0 || status.isFinished || status.isSeeding) return '--';
    final remaining = status.totalWanted - status.totalDone;
    if (remaining <= 0) return '--';
    final seconds = remaining / status.downloadRate;
    if (seconds < 60) return '${seconds.toInt()}s';
    if (seconds < 3600) return '${(seconds / 60).toInt()}m ${(seconds % 60).toInt()}s';
    return '${(seconds / 3600).toInt()}h ${((seconds % 3600) / 60).toInt()}m';
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
      body: _initError != null
          ? Center(child: Text('Error: $_initError', style: const TextStyle(color: Colors.red)))
          : !_initialized
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
                                final handle = _handles[index];
                                final statusList = _statuses.values.toList();
                                
                                if (index >= statusList.length) {
                                  // No status yet (waiting for first update cycle)
                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Connecting...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          SizedBox(height: 8),
                                          LinearProgressIndicator(),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final status = statusList[index];
                                final progress = (status.progress * 100).toStringAsFixed(1);
                                final displayName = status.name.isNotEmpty 
                                    ? status.name 
                                    : 'Torrent #${status.id}';
                                
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: InkWell(
                                    onTap: () => _showFiles(handle),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  displayName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: status.isSeeding
                                                      ? Colors.green.withValues(alpha: 0.2)
                                                      : Colors.blueAccent.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  status.stateString,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: status.isSeeding ? Colors.green : Colors.blueAccent,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: status.progress,
                                              minHeight: 6,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '$progress%  •  ${_formatBytes(status.totalDone)} / ${_formatBytes(status.totalWanted)}  •  ETA: ${_estimateEta(status)}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.arrow_downward, size: 14, color: Colors.green[300]),
                                              const SizedBox(width: 4),
                                              Text(_formatSpeed(status.downloadRate), style: TextStyle(fontSize: 12, color: Colors.green[300])),
                                              const SizedBox(width: 16),
                                              Icon(Icons.arrow_upward, size: 14, color: Colors.orange[300]),
                                              const SizedBox(width: 4),
                                              Text(_formatSpeed(status.uploadRate), style: TextStyle(fontSize: 12, color: Colors.orange[300])),
                                              const Spacer(),
                                              Icon(Icons.people_outline, size: 14, color: Colors.grey[500]),
                                              const SizedBox(width: 4),
                                              Text('${status.numPeers} (${status.numSeeds} seeds)', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Tap to view files',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
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
