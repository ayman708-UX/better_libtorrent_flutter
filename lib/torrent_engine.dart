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
  });

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
    );
  }
}

class TorrentEngine {
  static bool _initialized = false;

  /// Initializes the CA certificate bundle for secure tracker connections.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final bytes = await rootBundle.load('packages/better_libtorrent_flutter/assets/cacert.pem');
      
      // We don't have path_provider directly, but we can just use Directory.systemTemp
      // or require path_provider as a dependency. Wait, I'll use systemTemp to avoid adding dependencies
      // if path_provider isn't in pubspec.
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
    if (payload != nullptr) {
      final jsonStr = payload.cast<Utf8>().toDartString();
      
      // Free the C string allocated with strdup in C++
      final freeFunc = _dylib.lookupFunction<Void Function(Pointer<Char>), void Function(Pointer<Char>)>('te_free_string');
      freeFunc(payload);
      
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        if (data.containsKey('status')) {
          _alertController.add(TorrentStateUpdate.fromJson(data));
        } else {
          _alertController.add(TorrentAlert.fromJson(data));
        }
      } catch (e) {
        debugPrint('Error parsing alert JSON: $e');
      }
    }
  }

  static Future<TorrentSession> create({String? configJson}) async {
    await TorrentEngine.initialize();
    
    // We run the creation in a short-lived isolate to avoid blocking the main UI thread.
    // Return only the integer address to avoid SendPort/ReceivePort issues across isolates.
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

  Stream<TorrentAlert> get alerts => _alertController.stream;

  void pause() {
    _bindings.te_session_pause(_sessionPtr);
  }

  void resume() {
    _bindings.te_session_resume(_sessionPtr);
  }

  Future<TorrentHandle> addMagnet(String uri, {required String savePath}) async {
    final sessionAddress = _sessionPtr.address;
    
    final handleAddress = await Isolate.run(() {
      final sessionPtr = Pointer<te_session_t>.fromAddress(sessionAddress);
      final uriPtr = uri.toNativeUtf8();
      final savePathPtr = savePath.toNativeUtf8();
      
      final ptr = _bindings.te_add_magnet(
        sessionPtr,
        uriPtr.cast<Char>(),
        savePathPtr.cast<Char>(),
      );
      
      malloc.free(uriPtr);
      malloc.free(savePathPtr);
      
      return ptr.address;
    });
    
    final handlePtr = Pointer<te_torrent_handle_t>.fromAddress(handleAddress);
    
    if (handlePtr == nullptr) {
      throw Exception('Failed to add magnet link');
    }
    
    return TorrentHandle._(handlePtr);
  }

  Future<TorrentHandle> addTorrentFile(Uint8List bytes, {required String savePath}) async {
    final sessionAddress = _sessionPtr.address;
    
    final handleAddress = await Isolate.run(() {
      final sessionPtr = Pointer<te_session_t>.fromAddress(sessionAddress);
      
      final Pointer<Uint8> dataPtr = malloc.allocate<Uint8>(bytes.length);
      final dataList = dataPtr.asTypedList(bytes.length);
      dataList.setAll(0, bytes);
      
      final savePathPtr = savePath.toNativeUtf8();
      
      final ptr = _bindings.te_add_torrent_file(
        sessionPtr,
        dataPtr,
        bytes.length,
        savePathPtr.cast<Char>(),
      );
      
      malloc.free(dataPtr);
      malloc.free(savePathPtr);
      
      return ptr.address;
    });
    
    final handlePtr = Pointer<te_torrent_handle_t>.fromAddress(handleAddress);
    
    if (handlePtr == nullptr) {
      throw Exception('Failed to add torrent file');
    }
    
    return TorrentHandle._(handlePtr);
  }

  void remove(TorrentHandle handle, {bool deleteFiles = false}) {
    _bindings.te_torrent_remove(_sessionPtr, handle._handlePtr, deleteFiles);
  }

  void dispose() {
    _nativeCallable.close();
    _alertController.close();
    _bindings.te_session_destroy(_sessionPtr);
  }
}

class TorrentHandle {
  final Pointer<te_torrent_handle_t> _handlePtr;

  TorrentHandle._(this._handlePtr);

  void pause() {
    _bindings.te_torrent_pause(_handlePtr);
  }

  void resume() {
    _bindings.te_torrent_resume(_handlePtr);
  }

  void setSequentialDownload(bool enabled) {
    _bindings.te_torrent_set_sequential_download(_handlePtr, enabled);
  }

  void setFilePriority(int fileIndex, int priority) {
    _bindings.te_torrent_set_file_priority(_handlePtr, fileIndex, priority);
  }

  void setPieceDeadline(int pieceIndex, int deadline, {int flags = 0}) {
    _bindings.te_torrent_set_piece_deadline(_handlePtr, pieceIndex, deadline, flags);
  }
}
