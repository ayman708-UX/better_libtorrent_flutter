import 'package:flutter/material.dart';
import 'package:better_libtorrent_flutter/better_libtorrent_flutter.dart' as better_libtorrent_flutter;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late int pingResult;

  @override
  void initState() {
    super.initState();
    pingResult = better_libtorrent_flutter.ping();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Better Libtorrent Flutter')),
        body: Center(
          child: Text(
            'ping() = $pingResult',
            style: const TextStyle(fontSize: 25),
          ),
        ),
      ),
    );
  }
}
