
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
      title: 'Libtorrent Engine Advanced',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
        cardTheme: const CardThemeData(color: Color(0xFF2A2A3C), elevation: 2),
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
  
  // Track saved resume data to mock "Add from resume data"
  final Map<int, List<int>> _savedResumeData = {};

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Timer? _statusTimer;

  Future<void> _initEngine() async {
    try {
      _session = await TorrentSession.create();
      _session!.alerts.listen(_handleAlert);
      
      if (mounted) {
        setState(() => _initialized = true);
        
        // Start polling the UI to reflect getStatus()
        _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  void _handleAlert(TorrentAlert alert) {
    if (alert is TorrentStateUpdate) {
      setState(() {
        for (var status in alert.status) {
          _statuses[status.id] = status;
        }
      });
    } else if (alert is MetadataReceivedAlert) {
      setState(() {});
      _showToast('Metadata received for torrent!');
    } else if (alert is TorrentFinishedAlert) {
      _showToast('Download complete!');
    } else if (alert is SaveResumeDataAlert) {
      _savedResumeData[alert.torrentId ?? 0] = alert.resumeData;
      _showToast('Resume data saved (Size: ${alert.resumeData.length} bytes)');
    } else if (alert is ReadPieceAlert) {
      if (alert.error != null) {
        _showToast('Failed to read piece ${alert.piece}: ${alert.error}', error: true);
      } else {
        _showToast('Successfully read piece ${alert.piece} (Size: ${alert.size} bytes)');
      }
    } else if (alert is TorrentErrorAlert) {
      _showToast('Torrent error: ${alert.error}', error: true);
    } else if (alert.what == 'session_stats') {
      _showToast('Session stats update received in stream');
    }
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : Colors.grey[800],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addMagnet() async {
    if (_session == null) return;
    final uri = _magnetController.text.trim();
    if (uri.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final savePath = Directory('${dir.path}/Torrents');
    if (!await savePath.exists()) await savePath.create(recursive: true);

    try {
      final handle = _session!.addMagnet(uri, savePath: savePath.path);
      setState(() => _handles.add(handle));
      _showToast('Magnet added!');
    } catch (e) {
      _showToast('Error: $e', error: true);
    }
  }

  Future<void> _addFromResumeData(int torrentId) async {
    if (_session == null || !_savedResumeData.containsKey(torrentId)) {
      _showToast('No saved resume data for torrent #$torrentId', error: true);
      return;
    }
    
    final dir = await getApplicationDocumentsDirectory();
    final savePath = Directory('${dir.path}/Torrents');
    
    try {
      final handle = _session!.addTorrentWithResume(
        Uint8List.fromList(_savedResumeData[torrentId]!),
        savePath: savePath.path,
      );
      setState(() => _handles.add(handle));
      _showToast('Torrent resumed from saved data!');
    } catch (e) {
      _showToast('Error: $e', error: true);
    }
  }

  void _showGlobalSettings() {
    if (_session == null) return;
    final settings = _session!.getSettings();
    bool dhtRunning = _session!.isDhtRunning();
    
    int dlLimit = (settings.downloadRateLimit ?? 0) ~/ 1024;
    int ulLimit = (settings.uploadRateLimit ?? 0) ~/ 1024;
    int connLimit = settings.connectionsLimit ?? 200;
    bool enableDht = settings.enableDht ?? true;
    bool anonymousMode = settings.anonymousMode ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2A2A3C),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Global Session Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text('DHT Node Running: ${dhtRunning ? "Yes" : "No"}', style: TextStyle(color: dhtRunning ? Colors.green : Colors.red)),
                    SwitchListTile(
                      title: const Text('Enable DHT'),
                      value: enableDht,
                      onChanged: (val) {
                        setModalState(() => enableDht = val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Anonymous Mode'),
                      subtitle: const Text('Hides IP in some scenarios, restricts peer sources'),
                      value: anonymousMode,
                      onChanged: (val) {
                        setModalState(() => anonymousMode = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Global Download Limit: ${dlLimit == 0 ? "Unlimited" : "$dlLimit KB/s"}'),
                    Slider(
                      value: dlLimit.toDouble(), max: 10000, min: 0,
                      onChanged: (v) => setModalState(() => dlLimit = v.toInt()),
                    ),
                    Text('Global Upload Limit: ${ulLimit == 0 ? "Unlimited" : "$ulLimit KB/s"}'),
                    Slider(
                      value: ulLimit.toDouble(), max: 5000, min: 0,
                      onChanged: (v) => setModalState(() => ulLimit = v.toInt()),
                    ),
                    Text('Max Global Connections: $connLimit'),
                    Slider(
                      value: connLimit.toDouble(), max: 1000, min: 10,
                      onChanged: (v) => setModalState(() => connLimit = v.toInt()),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _session!.applySettings(SessionSettings(
                            downloadRateLimit: dlLimit * 1024,
                            uploadRateLimit: ulLimit * 1024,
                            connectionsLimit: connLimit,
                            enableDht: enableDht,
                            anonymousMode: anonymousMode,
                          ));
                          Navigator.pop(ctx);
                          _showToast('Global settings applied');
                        },
                        child: const Text('Apply Settings'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          _session!.postSessionStats();
                          _showToast('Requested session stats dump');
                        },
                        child: const Text('Post Session Stats'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      }
    );
  }

  void _showTorrentDetails(TorrentHandle handle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2A2A3C),
      builder: (ctx) => TorrentDetailsSheet(handle: handle, session: _session!),
    );
  }

  void _handleTorrentAction(String action, TorrentHandle handle) {
    switch (action) {
      case 'pause': handle.pause(); _showToast('Paused'); break;
      case 'resume': handle.resume(); _showToast('Resumed'); break;
      case 'force_reannounce': handle.forceReannounce(); _showToast('Force reannounce sent'); break;
      case 'force_recheck': handle.forceRecheck(); _showToast('Force recheck started'); break;
      case 'flush_cache': handle.flushCache(); _showToast('Cache flushed'); break;
      case 'save_resume': handle.saveResumeData(); _showToast('Requested resume data save...'); break;
      case 'move_storage':
        handle.moveStorage('/tmp/new_torrent_location'); 
        _showToast('Moved storage to /tmp/new_torrent_location'); 
        break;
      case 'remove_keep': 
        _session!.remove(handle, deleteFiles: false);
        setState(() => _handles.remove(handle));
        _showToast('Removed torrent (kept files)');
        break;
      case 'remove_delete':
        _session!.remove(handle, deleteFiles: true);
        setState(() => _handles.remove(handle));
        _showToast('Removed torrent and deleted files');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Libtorrent Advanced Demo'),
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showGlobalSettings,
              tooltip: 'Global Settings',
            ),
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: () { _session!.pause(); _showToast('Session Paused'); },
              tooltip: 'Pause All',
            ),
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () { _session!.resume(); _showToast('Session Resumed'); },
              tooltip: 'Resume All',
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
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _magnetController,
                                  decoration: const InputDecoration(labelText: 'Magnet URI', border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _addMagnet,
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _handles.isEmpty
                          ? const Center(child: Text('No torrents added. Add a magnet link.'))
                          : ListView.builder(
                              itemCount: _handles.length,
                              itemBuilder: (context, index) {
                                final handle = _handles[index];
                                
                                TorrentStatus? status;
                                try {
                                  status = handle.getStatus();
                                } catch (e) {
                                  return Card(margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(16), child: Text('Connecting... (or error: $e)')));
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: InkWell(
                                    onTap: () => _showTorrentDetails(handle),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(status.name.isEmpty ? 'Torrent #${status.id}' : status.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                              PopupMenuButton<String>(
                                                onSelected: (val) => _handleTorrentAction(val, handle),
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(value: 'pause', child: Text('Pause')),
                                                  const PopupMenuItem(value: 'resume', child: Text('Resume')),
                                                  const PopupMenuItem(value: 'force_reannounce', child: Text('Force Reannounce')),
                                                  const PopupMenuItem(value: 'force_recheck', child: Text('Force Recheck')),
                                                  const PopupMenuItem(value: 'save_resume', child: Text('Save Resume Data')),
                                                  const PopupMenuItem(value: 'flush_cache', child: Text('Flush Cache')),
                                                  const PopupMenuItem(value: 'move_storage', child: Text('Move Storage (/tmp)')),
                                                  const PopupMenuDivider(),
                                                  if (_savedResumeData.containsKey(status!.id))
                                                    PopupMenuItem(
                                                      child: const Text('Add from Saved Resume Data', style: TextStyle(color: Colors.green)),
                                                      onTap: () => Future.delayed(Duration.zero, () => _addFromResumeData(status!.id)),
                                                    ),
                                                  const PopupMenuDivider(),
                                                  const PopupMenuItem(value: 'remove_keep', child: Text('Remove (Keep files)')),
                                                  const PopupMenuItem(value: 'remove_delete', child: Text('Remove (Delete files)', style: TextStyle(color: Colors.red))),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(value: status.progress, minHeight: 6),
                                          const SizedBox(height: 8),
                                          Text('${(status.progress * 100).toStringAsFixed(1)}% • State: ${status.stateString}', style: const TextStyle(fontSize: 12)),
                                          Row(
                                            children: [
                                              Icon(Icons.arrow_downward, size: 14, color: Colors.green[300]),
                                              Text('${(status.downloadRate / 1024).toStringAsFixed(1)} KB/s', style: const TextStyle(fontSize: 12)),
                                              const SizedBox(width: 16),
                                              Icon(Icons.arrow_upward, size: 14, color: Colors.orange[300]),
                                              Text('${(status.uploadRate / 1024).toStringAsFixed(1)} KB/s', style: const TextStyle(fontSize: 12)),
                                              const Spacer(),
                                              Icon(Icons.people, size: 14, color: Colors.grey),
                                              Text('${status.numPeers} (${status.numSeeds} seeds)', style: const TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Text('Tap to view files, advanced info, and stream testing', style: TextStyle(fontSize: 11, color: Colors.blueAccent)),
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
    _statusTimer?.cancel();
    _session?.dispose();
    super.dispose();
  }
}

class TorrentDetailsSheet extends StatefulWidget {
  final TorrentHandle handle;
  final TorrentSession session;
  const TorrentDetailsSheet({super.key, required this.handle, required this.session});

  @override
  State<TorrentDetailsSheet> createState() => _TorrentDetailsSheetState();
}

class _TorrentDetailsSheetState extends State<TorrentDetailsSheet> {
  late TorrentStatus status;
  late Map<String, String> hashes;
  late TorrentPieceInfo? pieceInfo;
  late List<TorrentFile> files;
  late List<int> priorities;
  
  bool seqDownload = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    status = widget.handle.getStatus();
    hashes = widget.handle.getInfoHash();
    pieceInfo = widget.handle.getPieceInfo();
    files = widget.handle.getFiles();
    priorities = widget.handle.getFilePriorities();
    seqDownload = (widget.handle.getFlags() & 0x200) != 0; // TE_FLAG_SEQUENTIAL_DOWNLOAD
  }

  void _testStreamPiece(int pieceIndex) {
    if (widget.handle.havePiece(pieceIndex)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Piece $pieceIndex is already downloaded! Reading directly...')));
      widget.handle.readPiece(pieceIndex);
      return;
    }

    // Advanced streaming workflow:
    // 1. Clear previous deadlines
    widget.handle.clearPieceDeadlines();
    // 2. Set deadline for target piece (request within 1000ms)
    widget.handle.setPieceDeadline(pieceIndex, 1000);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Requested piece via deadline... waiting for download')));
  }

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const SizedBox(height: 300, child: Center(child: Text('Awaiting metadata...')));
    }

    return DefaultTabController(
      length: 2,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            const TabBar(tabs: [Tab(text: 'Files & Streaming'), Tab(text: 'Advanced Info')]),
            Expanded(
              child: TabBarView(
                children: [
                  // FILES TAB
                  Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Sequential Download (for streaming)'),
                        value: seqDownload,
                        onChanged: (v) {
                          widget.handle.setSequentialDownload(v);
                          setState(() => seqDownload = v);
                        },
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (ctx, idx) {
                            final file = files[idx];
                            final prio = priorities.length > idx ? priorities[idx] : 4;
                            return ListTile(
                              title: Text(file.name, style: const TextStyle(fontSize: 13)),
                              subtitle: Text('Size: ${file.size} B'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_fill, color: Colors.blueAccent),
                                    tooltip: 'Test Stream (Read piece 0)',
                                    onPressed: () => _testStreamPiece(0), // Simulating streaming start
                                  ),
                                  DropdownButton<int>(
                                    value: prio,
                                    items: const [
                                      DropdownMenuItem(value: 0, child: Text('Skip')),
                                      DropdownMenuItem(value: 1, child: Text('Low')),
                                      DropdownMenuItem(value: 4, child: Text('Normal')),
                                      DropdownMenuItem(value: 7, child: Text('High')),
                                    ],
                                    onChanged: (newPrio) {
                                      if (newPrio != null) {
                                        widget.handle.setFilePriority(idx, newPrio);
                                        setState(() => _loadData());
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  
                  // INFO TAB
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Hashes', style: TextStyle(fontWeight: FontWeight.bold)),
                      if (hashes.containsKey('v1')) Text('v1: ${hashes["v1"]}'),
                      if (hashes.containsKey('v2')) Text('v2: ${hashes["v2"]}'),
                      const Divider(),
                      const Text('Piece Info', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Total size: ${pieceInfo?.totalSize} B'),
                      Text('Piece length: ${pieceInfo?.pieceLength} B'),
                      Text('Total pieces: ${pieceInfo?.numPieces}'),
                      const Divider(),
                      const Text('Per-Torrent Limits', style: TextStyle(fontWeight: FontWeight.bold)),
                      ListTile(
                        title: const Text('Upload Rate Limit'),
                        trailing: Text('${widget.handle.getUploadLimit()} B/s'),
                        onTap: () { widget.handle.setUploadLimit(50 * 1024); setState((){}); },
                      ),
                      ListTile(
                        title: const Text('Download Rate Limit'),
                        trailing: Text('${widget.handle.getDownloadLimit()} B/s'),
                        onTap: () { widget.handle.setDownloadLimit(100 * 1024); setState((){}); },
                      ),
                      ListTile(
                        title: const Text('Max Connections'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () { widget.handle.setMaxConnections(50); _showToast('Max connections set to 50'); },
                      ),
                      ListTile(
                        title: const Text('Max Upload Slots'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () { widget.handle.setMaxUploads(10); _showToast('Max uploads set to 10'); },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
  }
}

