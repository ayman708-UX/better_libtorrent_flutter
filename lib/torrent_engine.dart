import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/bindings_generated.dart';

const String _libName = 'torrent_engine';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.executable();
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final BetterLibtorrentFlutterBindings _bindings = BetterLibtorrentFlutterBindings(_dylib);

// Cache te_free_string lookup once instead of per-callback
final void Function(Pointer<Char>) _freeString = _dylib
    .lookupFunction<Void Function(Pointer<Char>), void Function(Pointer<Char>)>('te_free_string');

/// Calls a C function that returns a heap-allocated char* and converts it to a Dart String,
/// then frees the C string. This is the canonical way to call any te_*() that returns char*.
String _readAndFreeString(Pointer<Char> ptr) {
  if (ptr == nullptr) return '';
  final str = ptr.cast<Utf8>().toDartString();
  _freeString(ptr);
  return str;
}

// =========================================================
// Data Classes
// =========================================================

/// Session-wide settings. All fields are optional; only non-null fields
/// are applied when calling [TorrentSession.applySettings].
class SessionSettings {
  int? downloadRateLimit;
  int? uploadRateLimit;
  int? connectionsLimit;
  bool? enableDht;
  bool? anonymousMode;
  String? listenInterfaces;
  String? userAgent;
  String? proxyHostname;
  int? proxyPort;
  /// 0=none, 1=socks4, 2=socks5, 3=socks5_pw, 4=http, 5=http_pw
  int? proxyType;
  String? proxyUsername;
  String? proxyPassword;
  /// 0=forced, 1=enabled, 2=disabled
  int? inEncPolicy;
  int? outEncPolicy;
  /// 1=plaintext, 2=rc4, 3=both
  int? allowedEncLevel;
  int? activeDownloads;
  int? activeSeeds;
  int? activeLimit;

  // High-performance streaming settings
  int? connectionSpeed;
  int? torrentConnectBoost;
  /// 0=prefer_tcp, 1=peer_proportional
  int? mixedModeAlgorithm;
  int? recvSocketBufferSize;
  int? sendSocketBufferSize;
  int? maxOutRequestQueue;
  int? maxAllowedInRequestQueue;
  bool? validateHttpsTrackers;
  bool? enableOsCache;

  SessionSettings({
    this.downloadRateLimit,
    this.uploadRateLimit,
    this.connectionsLimit,
    this.enableDht,
    this.anonymousMode,
    this.listenInterfaces,
    this.userAgent,
    this.proxyHostname,
    this.proxyPort,
    this.proxyType,
    this.proxyUsername,
    this.proxyPassword,
    this.inEncPolicy,
    this.outEncPolicy,
    this.allowedEncLevel,
    this.activeDownloads,
    this.activeSeeds,
    this.activeLimit,
    this.connectionSpeed,
    this.torrentConnectBoost,
    this.mixedModeAlgorithm,
    this.recvSocketBufferSize,
    this.sendSocketBufferSize,
    this.maxOutRequestQueue,
    this.maxAllowedInRequestQueue,
    this.validateHttpsTrackers,
    this.enableOsCache,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (downloadRateLimit != null) map['download_rate_limit'] = downloadRateLimit;
    if (uploadRateLimit != null) map['upload_rate_limit'] = uploadRateLimit;
    if (connectionsLimit != null) map['connections_limit'] = connectionsLimit;
    if (enableDht != null) map['enable_dht'] = enableDht;
    if (anonymousMode != null) map['anonymous_mode'] = anonymousMode;
    if (listenInterfaces != null) map['listen_interfaces'] = listenInterfaces;
    if (userAgent != null) map['user_agent'] = userAgent;
    if (proxyHostname != null) map['proxy_hostname'] = proxyHostname;
    if (proxyPort != null) map['proxy_port'] = proxyPort;
    if (proxyType != null) map['proxy_type'] = proxyType;
    if (proxyUsername != null) map['proxy_username'] = proxyUsername;
    if (proxyPassword != null) map['proxy_password'] = proxyPassword;
    if (inEncPolicy != null) map['in_enc_policy'] = inEncPolicy;
    if (outEncPolicy != null) map['out_enc_policy'] = outEncPolicy;
    if (allowedEncLevel != null) map['allowed_enc_level'] = allowedEncLevel;
    if (activeDownloads != null) map['active_downloads'] = activeDownloads;
    if (activeSeeds != null) map['active_seeds'] = activeSeeds;
    if (activeLimit != null) map['active_limit'] = activeLimit;
    if (connectionSpeed != null) map['connection_speed'] = connectionSpeed;
    if (torrentConnectBoost != null) map['torrent_connect_boost'] = torrentConnectBoost;
    if (mixedModeAlgorithm != null) map['mixed_mode_algorithm'] = mixedModeAlgorithm;
    if (recvSocketBufferSize != null) map['recv_socket_buffer_size'] = recvSocketBufferSize;
    if (sendSocketBufferSize != null) map['send_socket_buffer_size'] = sendSocketBufferSize;
    if (maxOutRequestQueue != null) map['max_out_request_queue'] = maxOutRequestQueue;
    if (maxAllowedInRequestQueue != null) map['max_allowed_in_request_queue'] = maxAllowedInRequestQueue;
    if (validateHttpsTrackers != null) map['validate_https_trackers'] = validateHttpsTrackers;
    if (enableOsCache != null) map['enable_os_cache'] = enableOsCache;
    return map;
  }

  factory SessionSettings.fromJson(Map<String, dynamic> json) {
    return SessionSettings(
      downloadRateLimit: json['download_rate_limit'] as int?,
      uploadRateLimit: json['upload_rate_limit'] as int?,
      connectionsLimit: json['connections_limit'] as int?,
      enableDht: json['enable_dht'] as bool?,
      anonymousMode: json['anonymous_mode'] as bool?,
      listenInterfaces: json['listen_interfaces'] as String?,
      userAgent: json['user_agent'] as String?,
      proxyHostname: json['proxy_hostname'] as String?,
      proxyPort: json['proxy_port'] as int?,
      proxyType: json['proxy_type'] as int?,
      proxyUsername: json['proxy_username'] as String?,
      proxyPassword: json['proxy_password'] as String?,
      inEncPolicy: json['in_enc_policy'] as int?,
      outEncPolicy: json['out_enc_policy'] as int?,
      allowedEncLevel: json['allowed_enc_level'] as int?,
      activeDownloads: json['active_downloads'] as int?,
      activeSeeds: json['active_seeds'] as int?,
      activeLimit: json['active_limit'] as int?,
      connectionSpeed: json['connection_speed'] as int?,
      torrentConnectBoost: json['torrent_connect_boost'] as int?,
      mixedModeAlgorithm: json['mixed_mode_algorithm'] as int?,
      recvSocketBufferSize: json['recv_socket_buffer_size'] as int?,
      sendSocketBufferSize: json['send_socket_buffer_size'] as int?,
      maxOutRequestQueue: json['max_out_request_queue'] as int?,
      maxAllowedInRequestQueue: json['max_allowed_in_request_queue'] as int?,
      validateHttpsTrackers: json['validate_https_trackers'] as bool?,
      enableOsCache: json['enable_os_cache'] as bool?,
    );
  }
}

/// A file inside a torrent.
class TorrentFile {
  final int index;
  final String name;
  final String path;
  final int size;

  TorrentFile({
    required this.index,
    required this.name,
    required this.path,
    required this.size,
  });

  factory TorrentFile.fromJson(Map<String, dynamic> json) {
    return TorrentFile(
      index: json['index'] as int,
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
    );
  }
}

/// Piece-level info for a torrent (useful for streaming engines).
class TorrentPieceInfo {
  final int numPieces;
  final int pieceLength;
  final int totalSize;

  TorrentPieceInfo({
    required this.numPieces,
    required this.pieceLength,
    required this.totalSize,
  });

  factory TorrentPieceInfo.fromJson(Map<String, dynamic> json) {
    return TorrentPieceInfo(
      numPieces: json['num_pieces'] as int,
      pieceLength: json['piece_length'] as int,
      totalSize: json['total_size'] as int,
    );
  }
}

// =========================================================
// Alert Classes
// =========================================================

/// Base alert class. All alerts from libtorrent are deserialized into
/// this class or a subclass.
class TorrentAlert {
  final int type;
  final String what;
  final String message;
  final int? torrentId;

  TorrentAlert({
    required this.type,
    required this.what,
    required this.message,
    this.torrentId,
  });

  factory TorrentAlert.fromJson(Map<String, dynamic> json) {
    return TorrentAlert(
      type: json['type'] as int,
      what: json['what'] as String,
      message: json['message'] as String,
      torrentId: json['torrent_id'] as int?,
    );
  }
}

/// Bulk status update for all active torrents. Fired every ~500ms.
class TorrentStateUpdate extends TorrentAlert {
  final List<TorrentStatus> status;

  TorrentStateUpdate({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.status,
  });

  factory TorrentStateUpdate.fromJson(Map<String, dynamic> json) {
    final statusList = (json['status'] as List)
        .map((e) => TorrentStatus.fromJson(e as Map<String, dynamic>))
        .toList();
    return TorrentStateUpdate(
      type: json['type'] as int,
      what: json['what'] as String,
      message: json['message'] as String,
      torrentId: json['torrent_id'] as int?,
      status: statusList,
    );
  }
}

/// Snapshot of a single torrent's state.
class TorrentStatus {
  final int id;
  final int state;
  final double progress;
  final int downloadRate;
  final int uploadRate;
  final int totalDone;
  final int totalWanted;
  final int numPeers;
  final int numSeeds;
  final int numPieces;
  final bool hasMetadata;
  final bool isSeeding;
  final bool isFinished;
  final String name;
  final String savePath;
  final int allTimeDownload;
  final int allTimeUpload;
  final int addedTime;
  final int completedTime;
  final int downloadPayloadRate;
  final int uploadPayloadRate;
  final int total;
  final int totalWantedDone;
  final int numConnections;
  final int listSeeds;
  final int listPeers;
  final String currentTracker;

  TorrentStatus({
    required this.id,
    required this.state,
    required this.progress,
    required this.downloadRate,
    required this.uploadRate,
    required this.totalDone,
    required this.totalWanted,
    required this.numPeers,
    required this.numSeeds,
    this.numPieces = 0,
    this.hasMetadata = false,
    this.isSeeding = false,
    this.isFinished = false,
    this.name = '',
    this.savePath = '',
    this.allTimeDownload = 0,
    this.allTimeUpload = 0,
    this.addedTime = 0,
    this.completedTime = 0,
    this.downloadPayloadRate = 0,
    this.uploadPayloadRate = 0,
    this.total = 0,
    this.totalWantedDone = 0,
    this.numConnections = 0,
    this.listSeeds = 0,
    this.listPeers = 0,
    this.currentTracker = '',
  });

  /// Human-readable state name.
  String get stateString {
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

  factory TorrentStatus.fromJson(Map<String, dynamic> json) {
    return TorrentStatus(
      id: json['id'] as int,
      state: json['state'] as int,
      progress: (json['progress'] as num).toDouble(),
      downloadRate: json['download_rate'] as int,
      uploadRate: json['upload_rate'] as int,
      totalDone: json['total_done'] as int,
      totalWanted: json['total_wanted'] as int,
      numPeers: json['num_peers'] as int,
      numSeeds: json['num_seeds'] as int,
      numPieces: (json['num_pieces'] as int?) ?? 0,
      hasMetadata: (json['has_metadata'] as bool?) ?? false,
      isSeeding: (json['is_seeding'] as bool?) ?? false,
      isFinished: (json['is_finished'] as bool?) ?? false,
      name: (json['name'] as String?) ?? '',
      savePath: (json['save_path'] as String?) ?? '',
      allTimeDownload: (json['all_time_download'] as int?) ?? 0,
      allTimeUpload: (json['all_time_upload'] as int?) ?? 0,
      addedTime: (json['added_time'] as int?) ?? 0,
      completedTime: (json['completed_time'] as int?) ?? 0,
      downloadPayloadRate: (json['download_payload_rate'] as int?) ?? 0,
      uploadPayloadRate: (json['upload_payload_rate'] as int?) ?? 0,
      total: (json['total'] as int?) ?? 0,
      totalWantedDone: (json['total_wanted_done'] as int?) ?? 0,
      numConnections: (json['num_connections'] as int?) ?? 0,
      listSeeds: (json['list_seeds'] as int?) ?? 0,
      listPeers: (json['list_peers'] as int?) ?? 0,
      currentTracker: (json['current_tracker'] as String?) ?? '',
    );
  }
}

/// Fired when a magnet link finishes downloading its metadata (.torrent info).
class MetadataReceivedAlert extends TorrentAlert {
  MetadataReceivedAlert({required super.type, required super.what, required super.message, super.torrentId});
}

/// Fired when a torrent finishes downloading all wanted pieces.
class TorrentFinishedAlert extends TorrentAlert {
  TorrentFinishedAlert({required super.type, required super.what, required super.message, super.torrentId});
}

/// Fired when resume data is successfully generated. Contains the
/// serialized resume data as bytes.
class SaveResumeDataAlert extends TorrentAlert {
  final Uint8List resumeData;
  SaveResumeDataAlert({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.resumeData,
  });
}

/// Fired when a piece is read from disk (after calling [TorrentHandle.readPiece]).
class ReadPieceAlert extends TorrentAlert {
  final int piece;
  final int size;
  final Uint8List? data;
  final String? error;
  ReadPieceAlert({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.piece,
    required this.size,
    this.data,
    this.error,
  });
}

/// Fired when a single file in the torrent finishes downloading.
class FileCompletedAlert extends TorrentAlert {
  final int fileIndex;
  FileCompletedAlert({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.fileIndex,
  });
}

/// Fired when a piece finishes downloading and passes hash check.
class PieceFinishedAlert extends TorrentAlert {
  final int piece;
  PieceFinishedAlert({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.piece,
  });
}

/// Fired on torrent errors (disk I/O, permission denied, etc.).
class TorrentErrorAlert extends TorrentAlert {
  final String error;
  TorrentErrorAlert({
    required super.type,
    required super.what,
    required super.message,
    super.torrentId,
    required this.error,
  });
}

// =========================================================
// TorrentEngine (CA cert init)
// =========================================================

class TorrentEngine {
  static bool _initialized = false;

  /// Initializes the CA certificate bundle for secure tracker connections.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final bytes = await rootBundle.load('packages/better_libtorrent_flutter/assets/cacert.pem');
      final pemFile = File('${Directory.systemTemp.path}/cacert.pem');
      await pemFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      
      final pemPathPtr = pemFile.path.toNativeUtf8();
      _bindings.te_set_ca_bundle_path(pemPathPtr.cast<Char>());
      malloc.free(pemPathPtr);
      _initialized = true;
    } catch (e) {
      debugPrint('Warning: Failed to load cacert.pem. HTTPS trackers may fail. $e');
    }
  }
}

// =========================================================
// TorrentSession
// =========================================================

class TorrentSession {
  final Pointer<te_session_t> _sessionPtr;
  final StreamController<TorrentAlert> _alertController = StreamController<TorrentAlert>.broadcast();
  late final NativeCallable<te_alert_callbackFunction> _nativeCallable;

  TorrentSession._(this._sessionPtr) {
    _nativeCallable = NativeCallable<te_alert_callbackFunction>.listener(_onAlert);
    _bindings.te_session_set_alert_callback(
      _sessionPtr,
      _nativeCallable.nativeFunction,
      nullptr,
    );
  }

  void _onAlert(int type, Pointer<Char> payload, Pointer<Void> userData) {
    if (payload == nullptr) return;
    
    final jsonStr = _readAndFreeString(payload);
    if (jsonStr.isEmpty) return;
    
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final alert = _parseAlert(data);
      _alertController.add(alert);
    } catch (e) {
      debugPrint('Error parsing alert JSON: $e');
    }
  }

  TorrentAlert _parseAlert(Map<String, dynamic> data) {
    final type = data['type'] as int;
    final what = data['what'] as String;
    final message = data['message'] as String;
    final torrentId = data['torrent_id'] as int?;

    // state_update_alert
    if (data.containsKey('status')) {
      return TorrentStateUpdate.fromJson(data);
    }

    // save_resume_data_alert
    if (data.containsKey('resume_data')) {
      return SaveResumeDataAlert(
        type: type, what: what, message: message, torrentId: torrentId,
        resumeData: base64Decode(data['resume_data'] as String),
      );
    }

    // read_piece_alert
    if (what == 'read_piece' && data.containsKey('piece') && data.containsKey('size')) {
      return ReadPieceAlert(
        type: type, what: what, message: message, torrentId: torrentId,
        piece: data['piece'] as int,
        size: data['size'] as int,
        data: data['data'] != null ? base64Decode(data['data'] as String) : null,
        error: data['error'] as String?,
      );
    }

    // metadata_received_alert
    if (data['metadata_received'] == true) {
      return MetadataReceivedAlert(type: type, what: what, message: message, torrentId: torrentId);
    }

    // torrent_finished_alert
    if (data['finished'] == true) {
      return TorrentFinishedAlert(type: type, what: what, message: message, torrentId: torrentId);
    }

    // file_completed_alert
    if (data.containsKey('file_index') && what == 'file_completed') {
      return FileCompletedAlert(
        type: type, what: what, message: message, torrentId: torrentId,
        fileIndex: data['file_index'] as int,
      );
    }

    // piece_finished_alert
    if (data.containsKey('piece') && what == 'piece_finished') {
      return PieceFinishedAlert(
        type: type, what: what, message: message, torrentId: torrentId,
        piece: data['piece'] as int,
      );
    }

    // torrent_error_alert
    if (data.containsKey('error') && what == 'torrent_error') {
      return TorrentErrorAlert(
        type: type, what: what, message: message, torrentId: torrentId,
        error: data['error'] as String,
      );
    }

    return TorrentAlert(type: type, what: what, message: message, torrentId: torrentId);
  }

  /// Creates a new torrent session. Session creation is done on a background
  /// isolate because it can take 100+ms on mobile devices.
  static Future<TorrentSession> create({String? configJson}) async {
    await TorrentEngine.initialize();
    
    final address = await Isolate.run(() {
      Pointer<Char> configPtr = nullptr;
      if (configJson != null) {
        configPtr = configJson.toNativeUtf8().cast<Char>();
      }
      
      final ptr = _bindings.te_session_create(configPtr);
      
      if (configPtr != nullptr) {
        malloc.free(configPtr);
      }
      
      if (ptr == nullptr) {
        throw Exception('Failed to create libtorrent session');
      }
      return ptr.address;
    });

    final ptr = Pointer<te_session_t>.fromAddress(address);
    return TorrentSession._(ptr);
  }

  /// Stream of all alerts from libtorrent. Listen on this to receive
  /// status updates, errors, metadata events, resume data, etc.
  Stream<TorrentAlert> get alerts => _alertController.stream;

  void pause() => _bindings.te_session_pause(_sessionPtr);
  void resume() => _bindings.te_session_resume(_sessionPtr);

  /// Applies session-wide settings. Only non-null fields are applied.
  void applySettings(SessionSettings settings) {
    final jsonStr = jsonEncode(settings.toJson());
    final ptr = jsonStr.toNativeUtf8().cast<Char>();
    _bindings.te_session_apply_settings(_sessionPtr, ptr);
    malloc.free(ptr);
  }

  /// Returns the current session settings.
  SessionSettings getSettings() {
    final ptr = _bindings.te_session_get_settings(_sessionPtr);
    final jsonStr = _readAndFreeString(ptr);
    return SessionSettings.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  /// Returns true if the DHT node is currently running.
  bool isDhtRunning() => _bindings.te_session_is_dht_running(_sessionPtr);

  /// Manually trigger a status update (normally happens every 500ms automatically).
  void postTorrentUpdates() => _bindings.te_session_post_torrent_updates(_sessionPtr);

  /// Request session-wide statistics (fires a session_stats_alert).
  void postSessionStats() => _bindings.te_session_post_session_stats(_sessionPtr);

  /// Add a torrent via magnet link.
  TorrentHandle addMagnet(String uri, {required String savePath}) {
    final uriPtr = uri.toNativeUtf8().cast<Char>();
    final savePathPtr = savePath.toNativeUtf8().cast<Char>();
    
    final ptr = _bindings.te_add_magnet(_sessionPtr, uriPtr, savePathPtr);
    
    malloc.free(uriPtr);
    malloc.free(savePathPtr);
    
    if (ptr == nullptr) {
      throw Exception('Failed to add magnet link');
    }
    
    return TorrentHandle._(ptr);
  }

  /// Add a torrent from a .torrent file's bytes.
  TorrentHandle addTorrentFile(Uint8List bytes, {required String savePath}) {
    final Pointer<Uint8> dataPtr = malloc.allocate<Uint8>(bytes.length);
    dataPtr.asTypedList(bytes.length).setAll(0, bytes);
    
    final savePathPtr = savePath.toNativeUtf8().cast<Char>();
    
    final ptr = _bindings.te_add_torrent_file(_sessionPtr, dataPtr, bytes.length, savePathPtr);
    
    malloc.free(dataPtr);
    malloc.free(savePathPtr);
    
    if (ptr == nullptr) {
      throw Exception('Failed to add torrent file');
    }
    
    return TorrentHandle._(ptr);
  }

  /// Add a torrent from previously saved resume data bytes.
  TorrentHandle addTorrentWithResume(Uint8List resumeData, {String? savePath}) {
    final Pointer<Uint8> dataPtr = malloc.allocate<Uint8>(resumeData.length);
    dataPtr.asTypedList(resumeData.length).setAll(0, resumeData);
    
    Pointer<Char> savePathPtr = nullptr;
    if (savePath != null) {
      savePathPtr = savePath.toNativeUtf8().cast<Char>();
    }
    
    final ptr = _bindings.te_add_torrent_with_resume(_sessionPtr, dataPtr, resumeData.length, savePathPtr);
    
    malloc.free(dataPtr);
    if (savePathPtr != nullptr) malloc.free(savePathPtr);
    
    if (ptr == nullptr) {
      throw Exception('Failed to add torrent from resume data');
    }
    
    return TorrentHandle._(ptr);
  }

  /// Remove a torrent from the session. Optionally delete downloaded files.
  void remove(TorrentHandle handle, {bool deleteFiles = false}) {
    _bindings.te_torrent_remove(_sessionPtr, handle._handlePtr, deleteFiles);
  }

  /// Dispose of this session. Must be called when done.
  void dispose() {
    _bindings.te_session_set_alert_callback(_sessionPtr, nullptr, nullptr);
    _bindings.te_session_destroy(_sessionPtr);
    _nativeCallable.close();
    _alertController.close();
  }
}

// =========================================================
// TorrentHandle
// =========================================================

class TorrentHandle {
  final Pointer<te_torrent_handle_t> _handlePtr;

  TorrentHandle._(this._handlePtr);

  // --- Status & Info ---

  /// Returns a full status snapshot of this torrent.
  TorrentStatus getStatus() {
    final ptr = _bindings.te_torrent_get_status(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    return TorrentStatus.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  /// Returns the torrent name (or empty string if metadata not yet received).
  String getName() {
    final ptr = _bindings.te_torrent_get_name(_handlePtr);
    return _readAndFreeString(ptr);
  }

  /// Returns the info hash(es) as a map with keys "v1" and/or "v2".
  Map<String, String> getInfoHash() {
    final ptr = _bindings.te_torrent_get_info_hash(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }

  /// Returns the number of files in this torrent (0 if no metadata yet).
  int getFileCount() => _bindings.te_torrent_get_file_count(_handlePtr);

  /// Returns the list of files in this torrent.
  /// Each file has: index, name, path, size.
  /// Returns empty list if metadata not yet received.
  List<TorrentFile> getFiles() {
    final ptr = _bindings.te_torrent_get_files(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    final list = jsonDecode(jsonStr) as List;
    return list.map((e) => TorrentFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns piece-level info: number of pieces, piece length, total size.
  /// Returns null if no metadata yet.
  TorrentPieceInfo? getPieceInfo() {
    final ptr = _bindings.te_torrent_get_piece_info(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (decoded.isEmpty) return null;
    return TorrentPieceInfo.fromJson(decoded);
  }

  // --- Control ---

  void pause() => _bindings.te_torrent_pause(_handlePtr);
  void resume() => _bindings.te_torrent_resume(_handlePtr);
  void forceReannounce() => _bindings.te_torrent_force_reannounce(_handlePtr);
  void forceRecheck() => _bindings.te_torrent_force_recheck(_handlePtr);
  void flushCache() => _bindings.te_torrent_flush_cache(_handlePtr);

  /// Request async save of resume data. Listen for [SaveResumeDataAlert]
  /// on the session's alert stream.
  void saveResumeData() => _bindings.te_torrent_save_resume_data(_handlePtr);

  /// Move the torrent's downloaded files to a new directory.
  void moveStorage(String newPath) {
    final ptr = newPath.toNativeUtf8().cast<Char>();
    _bindings.te_torrent_move_storage(_handlePtr, ptr);
    malloc.free(ptr);
  }

  // --- Streaming & Piece Control ---

  /// Enable or disable sequential download mode (pieces downloaded in order).
  void setSequentialDownload(bool enabled) {
    _bindings.te_torrent_set_sequential_download(_handlePtr, enabled);
  }

  /// Returns true if the given piece has been downloaded and hash-checked.
  bool havePiece(int index) => _bindings.te_torrent_have_piece(_handlePtr, index);

  /// Request an async read of a piece's data from disk.
  /// Listen for [ReadPieceAlert] on the session's alert stream.
  void readPiece(int index) => _bindings.te_torrent_read_piece(_handlePtr, index);

  /// Tell the engine to prioritize downloading a specific piece within
  /// [deadline] milliseconds. Essential for streaming engines.
  void setPieceDeadline(int pieceIndex, int deadline, {int flags = 0}) {
    _bindings.te_torrent_set_piece_deadline(_handlePtr, pieceIndex, deadline, flags);
  }

  void resetPieceDeadline(int pieceIndex) {
    _bindings.te_torrent_reset_piece_deadline(_handlePtr, pieceIndex);
  }

  void clearPieceDeadlines() => _bindings.te_torrent_clear_piece_deadlines(_handlePtr);

  // --- Piece Prioritization (sliding window streaming) ---

  /// Set the download priority of a single piece.
  /// Priority: 0 = don't download, 1 = low, 4 = normal, 7 = highest.
  /// This is THE key API for sliding window streaming — it tells libtorrent
  /// to completely skip downloading a piece (priority 0) vs deadlines which
  /// only prioritize order.
  void setPiecePriority(int pieceIndex, int priority) {
    _bindings.te_torrent_set_piece_priority(_handlePtr, pieceIndex, priority);
  }

  /// Returns the current download priorities for all pieces as a list.
  List<int> getPiecePriorities() {
    final ptr = _bindings.te_torrent_get_piece_priorities(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    final list = jsonDecode(jsonStr) as List;
    return list.cast<int>();
  }

  /// Set download priorities for all pieces at once (fast bulk update for
  /// window shifts). Each value: 0 = skip, 1 = low, 4 = normal, 7 = highest.
  void setAllPiecePriorities(List<int> priorities) {
    final Pointer<Int32> ptr = malloc.allocate<Int32>(priorities.length * sizeOf<Int32>());
    for (int i = 0; i < priorities.length; i++) {
      ptr[i] = priorities[i];
    }
    _bindings.te_torrent_set_all_piece_priorities(_handlePtr, ptr, priorities.length);
    malloc.free(ptr);
  }

  /// Returns the byte offset of a file within the torrent's piece space.
  /// Returns -1 if metadata is not available or index is invalid.
  /// Use this instead of summing previous file sizes — it correctly handles
  /// padding files in multi-file torrents.
  int getFileOffset(int fileIndex) {
    return _bindings.te_torrent_get_file_offset(_handlePtr, fileIndex);
  }

  // --- File Prioritization ---

  /// Set the download priority of a single file.
  /// Priority: 0=skip, 1=low, 4=default, 7=highest
  void setFilePriority(int fileIndex, int priority) {
    _bindings.te_torrent_set_file_priority(_handlePtr, fileIndex, priority);
  }

  /// Returns the current download priorities for all files.
  List<int> getFilePriorities() {
    final ptr = _bindings.te_torrent_get_file_priorities(_handlePtr);
    final jsonStr = _readAndFreeString(ptr);
    final list = jsonDecode(jsonStr) as List;
    return list.cast<int>();
  }

  /// Set download priorities for all files at once.
  void setAllFilePriorities(List<int> priorities) {
    final Pointer<Int32> ptr = malloc.allocate<Int32>(priorities.length * sizeOf<Int32>());
    for (int i = 0; i < priorities.length; i++) {
      ptr[i] = priorities[i];
    }
    _bindings.te_torrent_set_all_file_priorities(_handlePtr, ptr, priorities.length);
    malloc.free(ptr);
  }

  // --- Per-Torrent Limits ---

  /// Set upload rate limit in bytes/sec. -1 = unlimited.
  void setUploadLimit(int limit) => _bindings.te_torrent_set_upload_limit(_handlePtr, limit);

  /// Set download rate limit in bytes/sec. -1 = unlimited.
  void setDownloadLimit(int limit) => _bindings.te_torrent_set_download_limit(_handlePtr, limit);

  int getUploadLimit() => _bindings.te_torrent_get_upload_limit(_handlePtr);
  int getDownloadLimit() => _bindings.te_torrent_get_download_limit(_handlePtr);

  /// Set the maximum number of connections for this torrent.
  void setMaxConnections(int max) => _bindings.te_torrent_set_max_connections(_handlePtr, max);

  /// Set the maximum number of upload slots for this torrent.
  void setMaxUploads(int max) => _bindings.te_torrent_set_max_uploads(_handlePtr, max);

  // --- Flags ---

  void setFlags(int flags, int mask) {
    _bindings.te_torrent_set_flags(_handlePtr, flags, mask);
  }

  int getFlags() => _bindings.te_torrent_get_flags(_handlePtr);
}
