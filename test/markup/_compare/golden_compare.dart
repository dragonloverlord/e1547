// Runs every file in dmark/corpus/golden through both the Dart petitparser
// grammar and dmark via the Node bridge, then reports parse-by-parse
// equivalence. Used to drive the parity-iteration loop; not a unit test.
//
// Usage (from the e1547 package root):
//   dart run test/markup/_compare/golden_compare.dart
//   dart run test/markup/_compare/golden_compare.dart --limit=10
//   dart run test/markup/_compare/golden_compare.dart --only=1567
//
// Output:
//   - one line per file: PASS / DIFF / CRASH-DART / CRASH-DMARK
//   - on the first DIFF a short JSON-pointer style mismatch is printed
//   - final summary tally
//
// Dev-only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:e1547/markup/data/grammar.dart';

import '../_bridge/bridge.dart';
import '../conformance/_support/canonical.dart';
import 'diff.dart';

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final goldenDir = _resolveGoldenDir();
  final files = goldenDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dtext'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var selected = files;
  if (options.only != null) {
    selected = files
        .where((f) => f.uri.pathSegments.last.contains(options.only!))
        .toList();
  }
  if (options.limit != null) {
    selected = selected.take(options.limit!).toList();
  }

  stdout.writeln('comparing ${selected.length} golden files');

  final bridge = await DmarkBridge.start();
  final grammar = DTextGrammar();

  var pass = 0;
  var diff = 0;
  var crashDart = 0;
  var crashDmark = 0;
  final firstDiffs = <_FailRecord>[];

  try {
    for (final file in selected) {
      final name = file.uri.pathSegments.last;
      final source = file.readAsStringSync();

      Object? dartTree;
      try {
        dartTree = grammar.parse(source).toJson();
      } catch (e, st) {
        crashDart++;
        stdout.writeln('CRASH-DART $name: $e');
        if (options.verbose) stdout.writeln(st);
        if (firstDiffs.length < options.showCount) {
          firstDiffs.add(_FailRecord(name, 'crash-dart', e.toString()));
        }
        continue;
      }

      Object? dmarkTree;
      try {
        dmarkTree = await bridge.parse(source);
      } catch (e) {
        crashDmark++;
        stdout.writeln('CRASH-DMARK $name: $e');
        continue;
      }

      final d = diffAst(dmarkTree, dartTree);
      if (d == null) {
        pass++;
        if (options.verbose) stdout.writeln('PASS $name');
      } else {
        diff++;
        stdout.writeln('DIFF $name @ ${d.path.isEmpty ? "<root>" : d.path}');
        if (firstDiffs.length < options.showCount) {
          firstDiffs.add(_FailRecord(name, 'diff', oneLineDiff(d)));
        }
      }
    }
  } finally {
    await bridge.dispose();
  }

  stdout.writeln('');
  stdout.writeln('=== summary ===');
  stdout.writeln('pass:        $pass');
  stdout.writeln('diff:        $diff');
  stdout.writeln('crash-dart:  $crashDart');
  stdout.writeln('crash-dmark: $crashDmark');
  stdout.writeln('total:       ${selected.length}');

  if (firstDiffs.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('=== first ${firstDiffs.length} failures ===');
    for (final f in firstDiffs) {
      stdout.writeln('${f.kind.padRight(12)} ${f.name}');
      stdout.writeln('  ${f.detail}');
    }
  }

  if (diff > 0 || crashDart > 0) {
    exit(1);
  }
}

class _FailRecord {
  _FailRecord(this.name, this.kind, this.detail);
  final String name;
  final String kind;
  final String detail;
}

class _Options {
  _Options({
    required this.limit,
    required this.only,
    required this.verbose,
    required this.showCount,
  });
  final int? limit;
  final String? only;
  final bool verbose;
  final int showCount;
}

_Options _parseOptions(List<String> args) {
  int? limit;
  String? only;
  var verbose = false;
  var showCount = 5;
  for (final arg in args) {
    if (arg.startsWith('--limit=')) {
      limit = int.parse(arg.split('=')[1]);
    } else if (arg.startsWith('--only=')) {
      only = arg.split('=')[1];
    } else if (arg == '--verbose' || arg == '-v') {
      verbose = true;
    } else if (arg.startsWith('--show=')) {
      showCount = int.parse(arg.split('=')[1]);
    } else {
      stderr.writeln('unknown arg: $arg');
      exit(2);
    }
  }
  return _Options(
    limit: limit,
    only: only,
    verbose: verbose,
    showCount: showCount,
  );
}

Directory _resolveGoldenDir() {
  const rel = 'dmark/corpus/golden';
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final p = Directory('${dir.path}/$rel');
    if (p.existsSync()) return p;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('could not locate $rel relative to ${Directory.current}');
}

// Silences unused import warning for `canonicalTree` when diff is removed.
// ignore: unused_element
void _touch() => canonicalize(null);
