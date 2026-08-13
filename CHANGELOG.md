## 0.0.1

* Initial release of `better_libtorrent_flutter`.
* High-performance Dart FFI wrapper around `libtorrent` v2.1.1.
* Includes WebTorrent support (`-Dwebtorrent=ON`), DHT, UPnP, NAT-PMP, and HTTPS trackers.
* Exposes complete session settings (rate limits, proxy, listen interfaces, encryption).
* Exposes piece-level deadlines (`setPieceDeadline`, `readPiece`) for building custom video/audio streaming engines with seeking support.
* Multi-file torrent inspection and per-file priority controls.
* Support for magnet links, `.torrent` files, and resume data.
