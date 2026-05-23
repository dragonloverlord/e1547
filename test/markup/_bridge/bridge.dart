// Dart-side bridge to the Node dmark parser.
//
// One long-lived `node parse.mjs` process per [DmarkBridge]. Inputs are
// queued, written as line-framed JSON, and matched back by request id
// when the response line arrives. Results are cached by input so
// re-parsing the same fixture during the iteration loop is free.
//
// Lifetime: a single bridge instance is shared across the conformance
// suite via [sharedDmarkBridge]. Call [disposeSharedDmarkBridge] in a
// teardownAll() block if you want deterministic shutdown.
//
// Dev-only. Deleted in commit 2.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _bridgeScriptRelPath = 'test/markup/_bridge/parse.mjs';

class DmarkBridgeException implements Exception {
  DmarkBridgeException(this.message);
  final String message;
  @override
  String toString() => 'DmarkBridgeException: $message';
}

class DmarkBridge {
  DmarkBridge._(this._proc);

  final Process _proc;
  final Map<String, Completer<Object?>> _pending = {};
  final Map<String, Object?> _cache = {};
  int _nextId = 0;
  bool _closed = false;
  late final StreamSubscription<String> _stdoutSub;

  static Future<DmarkBridge> start() async {
    final cwd = _findBridgeCwd();
    if (!Directory('${cwd.path}/node_modules/dmark').existsSync()) {
      throw DmarkBridgeException(
        'dmark not installed under ${cwd.path}/node_modules. '
        'Run `yarn install` in ${cwd.path} first.',
      );
    }
    final proc = await Process.start('node', [
      '${cwd.path}/parse.mjs',
    ], workingDirectory: cwd.path);
    final bridge = DmarkBridge._(proc);
    bridge._wire();
    return bridge;
  }

  void _wire() {
    _stdoutSub = _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: _onError, onDone: _onDone);
    _proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[dmark-bridge stderr] $line'));
  }

  /// Parses [input] through dmark and returns the AST as a plain
  /// JSON-style Dart tree (Map / List / scalar). Cached by input.
  Future<Object?> parse(String input) async {
    if (_closed) {
      throw DmarkBridgeException('bridge already disposed');
    }
    if (_cache.containsKey(input)) {
      return _cache[input];
    }
    final id = (_nextId++).toString();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _proc.stdin.add(
      utf8.encode('${json.encode({'id': id, 'input': input})}\n'),
    );
    final result = await completer.future;
    _cache[input] = result;
    return result;
  }

  /// Parses many inputs. Pipelines writes so a long corpus does not
  /// pay one round-trip per input.
  Future<List<Object?>> parseAll(Iterable<String> inputs) =>
      Future.wait(inputs.map(parse));

  /// Runs `parseDTextToAST(input)` inside Node for [iterations] consecutive
  /// passes and returns the total wall-clock microseconds. The IPC cost is
  /// a single round-trip regardless of iteration count, so this is the
  /// honest "how fast is dmark by itself" measurement.
  Future<int> measureMicros(String input, int iterations) async {
    if (_closed) {
      throw DmarkBridgeException('bridge already disposed');
    }
    final id = (_nextId++).toString();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _proc.stdin.add(
      utf8.encode(
        '${json.encode({'id': id, 'input': input, 'measure': iterations})}\n',
      ),
    );
    final result = await completer.future;
    if (result is! int) {
      throw DmarkBridgeException(
        'expected micros from measure frame, got $result',
      );
    }
    return result;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      _proc.stdin.add(utf8.encode('EXIT\n'));
      await _proc.stdin.flush();
      await _proc.stdin.close();
    } on Object catch (_) {
      // Node may have already exited; that is fine.
    }
    await _stdoutSub.cancel();
    await _proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final err = DmarkBridgeException('bridge disposed');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    Map<String, dynamic> frame;
    try {
      frame = json.decode(line) as Map<String, dynamic>;
    } on Object catch (_) {
      stderr.writeln('[dmark-bridge] bad frame from node: $line');
      return;
    }
    final id = frame['id'] as String?;
    if (id == null) {
      stderr.writeln('[dmark-bridge] unsolicited frame: $line');
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null) {
      stderr.writeln('[dmark-bridge] no waiter for id $id');
      return;
    }
    final error = frame['error'];
    if (error != null) {
      completer.completeError(DmarkBridgeException(error.toString()));
      return;
    }
    if (frame.containsKey('micros')) {
      completer.complete(frame['micros']);
      return;
    }
    completer.complete(frame['ast']);
  }

  void _onError(Object e, StackTrace s) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(e, s);
    }
    _pending.clear();
  }

  void _onDone() {
    if (_pending.isEmpty) return;
    final err = DmarkBridgeException('node bridge closed unexpectedly');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  static Directory _findBridgeCwd() {
    // Walk upwards until we find the bridge directory. Robust to whichever
    // working dir flutter test happens to pick.
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = Directory('${dir.path}/$_bridgeScriptRelPath').parent;
      if (File('${candidate.path}/parse.mjs').existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    throw DmarkBridgeException(
      'could not locate $_bridgeScriptRelPath from ${Directory.current.path}',
    );
  }
}

DmarkBridge? _shared;

/// Lazily-initialized bridge shared across the conformance suite.
Future<DmarkBridge> sharedDmarkBridge() async {
  return _shared ??= await DmarkBridge.start();
}

Future<void> disposeSharedDmarkBridge() async {
  final b = _shared;
  _shared = null;
  if (b != null) await b.dispose();
}
