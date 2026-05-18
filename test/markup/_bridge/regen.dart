// Regenerates the frozen expected JSON in every conformance fixture file.
//
// Usage (from the package root):
//   dart run test/markup/_bridge/regen.dart                 # all categories
//   dart run test/markup/_bridge/regen.dart blocks links    # specific ones
//
// For every entry in test/markup/conformance/fixtures/<category>.json the
// `input` field is run through dmark via the Node bridge and the resulting
// AST tree is written into the `expected` field. Entries without an
// `input` field abort the run with a clear error. Output is pretty-printed
// with alpha-sorted keys so diffs are minimal across runs.
//
// Dev-only. Deleted in commit 2.

import 'dart:convert';
import 'dart:io';

import '../conformance/_support/canonical.dart';
import 'bridge.dart';

const _categories = ['blocks', 'inline', 'links', 'paragraph', 'edge'];

Future<void> main(List<String> args) async {
  final categories = args.isEmpty ? _categories : args;
  for (final c in categories) {
    if (!_categories.contains(c)) {
      stderr.writeln(
        'unknown category "$c". known: ${_categories.join(", ")}',
      );
      exit(2);
    }
  }
  final bridge = await DmarkBridge.start();
  var total = 0;
  var changed = 0;
  try {
    for (final category in categories) {
      final result = await _regenCategory(category, bridge);
      total += result.total;
      changed += result.changed;
    }
  } finally {
    await bridge.dispose();
  }
  stdout.writeln('regen complete: $changed/$total fixtures rewritten');
}

class _Result {
  _Result(this.total, this.changed);
  final int total;
  final int changed;
}

Future<_Result> _regenCategory(String category, DmarkBridge bridge) async {
  final path = _resolveFixturePath(category);
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('no fixture file at $path. create it with seed entries');
  }
  final raw = file.readAsStringSync();
  final entries = (json.decode(raw) as List).cast<Map<String, dynamic>>();

  // Parse every input concurrently through the pipelined bridge so a large
  // corpus does not pay one round-trip per fixture.
  final asts = await Future.wait(
    entries.map((e) async {
      final input = e['input'];
      if (input is! String) {
        throw StateError(
          'fixture "${e['label']}" in $category.json has no input',
        );
      }
      return bridge.parse(input);
    }),
  );

  var changed = 0;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final newExpected = canonicalTree(asts[i]);
    final oldCanonical = entry['expected'] == null
        ? null
        : canonicalize(entry['expected']);
    final newCanonical = canonicalize(newExpected);
    if (oldCanonical != newCanonical) {
      changed++;
    }
    entry['expected'] = newExpected;
  }

  // Stable on-disk ordering: keep author-supplied entry order, but sort
  // keys inside each entry alpha-first so the file is diff-friendly.
  final ordered = entries.map(_stableEntry).toList();
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(ordered)}\n');

  stdout.writeln(
    'regen $category: ${entries.length} fixtures '
    '(${changed > 0 ? "$changed changed" : "no changes"})',
  );
  return _Result(entries.length, changed);
}

/// Re-sorts entry-level keys (label, input, expected, plus any future
/// metadata) for a stable on-disk layout. Entry payload keys inside
/// `expected` are already alpha-sorted by canonicalTree.
Map<String, Object?> _stableEntry(Map<String, dynamic> entry) {
  final keys = entry.keys.toList()..sort();
  return {for (final k in keys) k: entry[k]};
}

String _resolveFixturePath(String category) {
  const rel = 'test/markup/conformance/fixtures';
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final p = '${dir.path}/$rel/$category.json';
    if (File(p).existsSync()) return p;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'fixture file $category.json not found under $rel '
    '(searched up from ${Directory.current.path})',
  );
}
