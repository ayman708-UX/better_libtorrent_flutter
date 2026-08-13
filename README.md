# better_libtorrent_flutter

A high-performance Flutter Dart FFI plugin wrapping **libtorrent v2.1.1**. Works cross-platform across Windows, macOS, Linux, Android, and iOS.

Supports **WebTorrent** (`-Dwebtorrent=ON`), magnet links, `.torrent` files, file inspection, priority selection, sequential downloads, and piece deadlines for building **custom streaming engines with seek support**.

---

## Features

- **High-Performance FFI Bridge**: Direct native bindings to C++ libtorrent 2.1.1 without method channel overhead.
- **WebTorrent Support**: Built with `-Dwebtorrent=ON` for WebTorrent/WebSocket peer discovery.
- **Streaming Primitives**: Exposes `setPieceDeadline`, `clearPieceDeadlines`, `readPiece`, `havePiece`, and sequential mode for video/audio streaming with seeking.
- **File Management**: Inspect multi-file torrent contents, file sizes, and set individual file download priorities (skip, low, normal, high).
- **Session Configuration**: Configure download/upload rate limits, max connections, listen interfaces, DHT, proxies, and encryption policies.
- **Alert Stream**: Type-safe Dart event stream for status updates, metadata arrival, download progress, completed files, resume data, and errors.
- **Cross-Platform**: Pre-configured build systems for Windows, macOS, Linux, Android (NDK), and iOS.

---

## Installation

Add `better_libtorrent_flutter` to your `pubspec.yaml`:

```yaml
dependencies:
  better_libtorrent_flutter: ^0.0.1
```

---

## Usage

### 1. Create a Session & Add Magnet Link

```dart
import 'package:better_libtorrent_flutter/torrent_engine.dart';

void main() async {
  // Create a libtorrent session
  final session = await TorrentSession.create();

  // Listen to alerts (progress, metadata, completion, errors)
  session.alerts.listen((alert) {
    if (alert is TorrentStateUpdate) {
      for (var status in alert.status) {
        print('${status.name}: ${(status.progress * 100).toStringAsFixed(1)}% @ ${status.downloadRate / 1024} KB/s');
      }
    } else if (alert is MetadataReceivedAlert) {
      print('Metadata loaded for torrent!');
    } else if (alert is TorrentFinishedAlert) {
      print('Download complete!');
    }
  });

  // Add magnet link
  final handle = session.addMagnet(
    'magnet:?xt=urn:btih:...',
    savePath: '/path/to/downloads',
  );
}
```

---

### 2. Inspecting Files & Prioritization

Once metadata is received, you can list all files inside the torrent and set download priorities:

```dart
// Get list of files
List<TorrentFile> files = handle.getFiles();

for (var file in files) {
  print('[${file.index}] ${file.name} - ${file.size} bytes');
}

// Skip downloading file #0
handle.setFilePriority(0, 0); // 0 = Skip

// Prioritize file #1 for high priority
handle.setFilePriority(1, 7); // 7 = Highest priority
```

---

### 3. Video / Audio Streaming & Seeking

To build a streaming engine (e.g., serving video to a local HTTP server):

```dart
// Enable sequential downloading (download pieces in order)
handle.setSequentialDownload(true);

// Get piece metadata
TorrentPieceInfo? pieceInfo = handle.getPieceInfo();

// When the player seeks to a specific byte location, calculate the piece index:
int targetPieceIndex = 42;

// Clear previous deadlines and prioritize the new target piece
handle.clearPieceDeadlines();
handle.setPieceDeadline(targetPieceIndex, 500); // Need piece 42 within 500ms

// Check if a piece is ready
if (handle.havePiece(targetPieceIndex)) {
  // Read the piece bytes asynchronously
  handle.readPiece(targetPieceIndex);
}
```

Listen for `ReadPieceAlert` on `session.alerts` to retrieve the `Uint8List` buffer.

---

### 4. Configuring Session Settings

```dart
session.applySettings(SessionSettings(
  downloadRateLimit: 5 * 1024 * 1024, // 5 MB/s
  uploadRateLimit: 1 * 1024 * 1024,   // 1 MB/s
  connectionsLimit: 200,
  enableDht: true,
  anonymousMode: false,
));
```

---

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See [LICENSE](LICENSE) for details.
