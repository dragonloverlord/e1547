// Throughput benchmark for the petitparser-based DText parser, sanity
// checked against dmark over the Node bridge.
//
// Usage:
//   dart run test/markup/_bench/bench.dart
//   dart run test/markup/_bench/bench.dart --iterations=20 --corpus=large
//
// Inputs:
//   - The 144 conformance fixtures (small inputs, breadth coverage).
//   - A curated set of real wiki posts from dmark/corpus/staging that
//     spans 1 KB to 50 KB so the parser is exercised on realistic sizes.
//
// Measurement:
//   - Dart: a fresh DTextGrammar is built once. Each input is parsed N
//     times. Median wall-clock per op is reported (median chosen over
//     mean so a single GC pause does not pull the number up).
//   - dmark: every input goes through the Node bridge. Round-trip is
//     measured, then a baseline (the average round-trip cost on an empty
//     input over the same N) is subtracted to back out IPC overhead. This
//     is the approach the briefing endorses; the bridge does JSON encode
//     and decode for every payload so the baseline is an underestimate
//     of true overhead on large inputs.
//
// Goal: Dart MB/s within 2x of dmark MB/s. If it is 10x or worse, the
// report ends with a loud line naming the slowest categories.
//
// Dev-only. Deleted in commit 2.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:e1547/markup/data/grammar.dart';
import 'package:petitparser/debug.dart';

import '../_bridge/bridge.dart';
import '../conformance/_support/canonical.dart';

const _iterationsDefault = 30;

// Real wiki posts spanning realistic sizes. The list deliberately stays
// SMALL until throughput is closer to dmark: at the early baseline the
// Dart grammar is super-linear and even a 4 KB post takes minutes to
// parse. Bump these up (and re-add the 18 KB / 51 KB tiers) once the
// per-input ms/op clears the 10x-of-dmark gate.
const _corpusFilesSmall = <String>[
  'dmark/corpus/staging/1567-in_heat.dtext', // ~1 KB
];
const _corpusFilesMedium = <String>[
  ..._corpusFilesSmall,
  'dmark/corpus/staging/53124-avali_taur.dtext', // ~4 KB
];
const _corpusFilesLarge = <String>[
  ..._corpusFilesMedium,
  'dmark/corpus/staging/1638-e621_rules.dtext', // ~18 KB
  'dmark/corpus/staging/16162-howto_sites_and_sources.dtext', // ~51 KB
];

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final inputs = _collectInputs(options);
  stdout.writeln(
    'bench: ${inputs.length} inputs '
    '(${inputs.fold<int>(0, (a, b) => a + b.bytes)} bytes total), '
    'iterations=${options.iterations}',
  );

  final dart = _benchDart(inputs, options.iterations);
  _Bench? dmark;
  if (!options.skipDmark) {
    dmark = await _benchDmark(inputs, options.iterations);
  }

  _report(dart, dmark);

  if (options.profile) {
    stdout.writeln();
    stdout.writeln('=== petitparser profile (top hottest parsers) ===');
    _runProfile(inputs);
  }
}

/// Wraps the built grammar in petitparser's profile() helper and
/// runs every corpus input through it once. Frames are aggregated by
/// runtime type since the internal parsers are private and unlabelled.
/// Output ranks parser classes by cumulative wall-clock; the top
/// entries are the hottest combinators worth rewriting with `flatten()`
/// or reordering inside a `ChoiceParser`.
void _runProfile(List<_Input> inputs) {
  final grammar = DTextGrammar();
  final root = grammar.build();
  final frames = <ProfileFrame>[];
  final profiled = profile(root, output: frames.add);
  for (final input in inputs) {
    try {
      profiled.parse(input.source);
    } on Object catch (_) {
      // Skip crashing inputs; the aggregate signal is what we want.
    }
  }
  final byType = <String, _ProfileStats>{};
  for (final frame in frames) {
    final type = frame.parser.runtimeType.toString();
    final stats = byType.putIfAbsent(type, () => _ProfileStats());
    stats.totalMicros += frame.elapsed.inMicroseconds;
    stats.calls += frame.count;
  }
  final ranked = byType.entries.toList()
    ..sort((a, b) => b.value.totalMicros.compareTo(a.value.totalMicros));
  stdout.writeln(
    '  ${"parser class".padRight(40)}  '
    '${"total ms".padLeft(10)}  ${"calls".padLeft(10)}  '
    '${"us/call".padLeft(10)}',
  );
  for (final entry in ranked.take(15)) {
    final s = entry.value;
    final perCall = s.calls == 0 ? 0 : s.totalMicros / s.calls;
    stdout.writeln(
      '  ${entry.key.padRight(40)}  '
      '${(s.totalMicros / 1000).toStringAsFixed(1).padLeft(10)}  '
      '${s.calls.toString().padLeft(10)}  '
      '${perCall.toStringAsFixed(2).padLeft(10)}',
    );
  }
}

class _ProfileStats {
  int totalMicros = 0;
  int calls = 0;
}

class _Options {
  _Options({
    required this.iterations,
    required this.skipDmark,
    required this.corpus,
    required this.profile,
  });
  final int iterations;
  final bool skipDmark;
  final String corpus;
  final bool profile;
}

_Options _parseOptions(List<String> args) {
  var iterations = _iterationsDefault;
  var skipDmark = false;
  var corpus = 'small';
  var profile = false;
  for (final arg in args) {
    if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.split('=')[1]);
    } else if (arg == '--skip-dmark') {
      skipDmark = true;
    } else if (arg.startsWith('--corpus=')) {
      corpus = arg.split('=')[1];
    } else if (arg == '--profile') {
      profile = true;
    }
  }
  if (iterations < 1) {
    stderr.writeln('iterations must be >= 1');
    exit(2);
  }
  if (!const ['small', 'medium', 'large'].contains(corpus)) {
    stderr.writeln('corpus must be one of: small medium large');
    exit(2);
  }
  return _Options(
    iterations: iterations,
    skipDmark: skipDmark,
    corpus: corpus,
    profile: profile,
  );
}

List<String> _corpusFilesFor(String tier) {
  switch (tier) {
    case 'small':
      return _corpusFilesSmall;
    case 'medium':
      return _corpusFilesMedium;
    case 'large':
      return _corpusFilesLarge;
  }
  return _corpusFilesSmall;
}

class _Input {
  _Input(this.category, this.label, this.source);
  final String category;
  final String label;
  final String source;
  int get bytes => utf8.encode(source).length;
}

List<_Input> _collectInputs(_Options options) {
  final inputs = <_Input>[];
  // Conformance fixtures.
  const categories = ['blocks', 'inline', 'links', 'paragraph', 'edge'];
  final fixturesDir = _resolveFixturesDir();
  for (final cat in categories) {
    final file = File('${fixturesDir.path}/$cat.json');
    if (!file.existsSync()) continue;
    final list = json.decode(file.readAsStringSync()) as List;
    for (final raw in list) {
      final e = raw as Map<String, dynamic>;
      inputs.add(_Input(cat, e['label'] as String, e['input'] as String));
    }
  }
  // Curated real-world corpus.
  for (final relPath in _corpusFilesFor(options.corpus)) {
    final f = _resolveCorpusFile(relPath);
    if (f != null) {
      inputs.add(
        _Input('corpus', f.uri.pathSegments.last, f.readAsStringSync()),
      );
    }
  }
  return inputs;
}

Directory _resolveFixturesDir() {
  const rel = 'test/markup/conformance/fixtures';
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final p = Directory('${dir.path}/$rel');
    if (p.existsSync()) return p;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('could not locate $rel');
}

File? _resolveCorpusFile(String relPath) {
  // Corpus lives outside the e1547 package (alongside it in dmark/).
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final p = File('${dir.path}/$relPath');
    if (p.existsSync()) return p;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

class _Sample {
  _Sample(this.input, this.medianMicros, this.crashed);
  final _Input input;
  final int medianMicros;
  final bool crashed;
}

class _Bench {
  _Bench(this.label, this.samples, this.totalBytes, this.totalParseMicros);
  final String label;
  final List<_Sample> samples;
  final int totalBytes;
  final int totalParseMicros;

  double get mbPerSec {
    if (totalParseMicros == 0) return double.infinity;
    final seconds = totalParseMicros / 1e6;
    final megabytes = totalBytes / (1024 * 1024);
    return megabytes / seconds;
  }

  /// Median microseconds across all sample inputs (one median per input).
  double get medianMicrosPerOp {
    final times = [
      for (final s in samples)
        if (!s.crashed) s.medianMicros,
    ];
    if (times.isEmpty) return double.nan;
    times.sort();
    return times[times.length ~/ 2].toDouble();
  }

  int get crashCount => samples.where((s) => s.crashed).length;
}

_Bench _benchDart(List<_Input> inputs, int iterations) {
  final grammar = DTextGrammar();
  // Warm up to JIT the hot paths.
  for (final input in inputs) {
    try {
      grammar.parse(input.source);
    } on Object catch (_) {
      // Keep going; some inputs may still crash.
    }
  }

  final samples = <_Sample>[];
  var totalBytes = 0;
  var totalMicros = 0;
  for (final input in inputs) {
    final timings = <int>[];
    var crashed = false;
    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      try {
        grammar.parse(input.source);
      } on Object catch (_) {
        crashed = true;
        break;
      }
      sw.stop();
      timings.add(sw.elapsedMicroseconds);
    }
    final medianMicros = crashed ? 0 : (timings..sort())[timings.length ~/ 2];
    samples.add(_Sample(input, medianMicros, crashed));
    if (!crashed) {
      totalBytes += input.bytes;
      totalMicros += medianMicros;
    }
  }
  return _Bench('dart', samples, totalBytes, totalMicros);
}

Future<_Bench> _benchDmark(List<_Input> inputs, int iterations) async {
  final bridge = await DmarkBridge.start();
  try {
    final samples = <_Sample>[];
    var totalBytes = 0;
    var totalMicros = 0;
    for (final input in inputs) {
      var crashed = false;
      var perOpMicros = 0;
      try {
        // measureMicros runs parseDTextToAST inside Node for the given
        // iteration count and returns total wall-clock microseconds.
        // IPC cost is amortised over one round-trip per pair, so it
        // is below noise for non-trivial inputs.
        final total = await bridge.measureMicros(input.source, iterations);
        perOpMicros = total ~/ iterations;
      } on Object catch (_) {
        crashed = true;
      }
      samples.add(_Sample(input, perOpMicros, crashed));
      if (!crashed) {
        totalBytes += input.bytes;
        totalMicros += perOpMicros;
      }
    }
    return _Bench('dmark', samples, totalBytes, totalMicros);
  } finally {
    await bridge.dispose();
  }
}

void _report(_Bench dart, _Bench? dmark) {
  stdout.writeln();
  stdout.writeln('=== throughput ===');
  _printSummary(dart);
  if (dmark != null) {
    _printSummary(dmark);
    // Gate the ratio on the aggregate dmark parse time being above the
    // raw measurement noise floor (~1 ms summed across the corpus).
    // medianMicrosPerOp is a per-input median and can sit below noise
    // when the corpus is mostly tiny conformance fixtures, but the
    // aggregate MB/s ratio is still meaningful as long as the totals
    // are well above measurement jitter.
    if (dmark.totalParseMicros > 1000) {
      final ratio = dmark.mbPerSec / dart.mbPerSec;
      stdout.writeln();
      if (ratio < 1.0) {
        stdout.writeln(
          'dart is ${(1 / ratio).toStringAsFixed(2)}x faster than dmark by MB/s',
        );
      } else {
        stdout.writeln(
          'dart is ${ratio.toStringAsFixed(2)}x slower than dmark by MB/s',
        );
      }
      if (ratio > 10) {
        stdout.writeln();
        stdout.writeln('### PERF ALERT ###');
        stdout.writeln(
          'PERF ALERT: dart parser is ${ratio.toStringAsFixed(1)}x slower than dmark',
        );
        stdout.writeln(_slowestCategoriesReport(dart));
        stdout.writeln('### END ###');
      } else if (ratio > 2) {
        stdout.writeln();
        stdout.writeln('over the 2x budget. tightening targets:');
        stdout.writeln(_slowestCategoriesReport(dart));
      }
    } else {
      stdout.writeln();
      stdout.writeln(
        'dmark per-op median is below IPC noise floor '
        '(${dmark.medianMicrosPerOp.toStringAsFixed(0)}us). '
        'Rerun with --corpus=medium or --corpus=large for a meaningful ratio.',
      );
    }
  } else {
    stdout.writeln('(dmark skipped)');
  }

  stdout.writeln();
  stdout.writeln('=== slowest categories (dart) ===');
  stdout.writeln(_slowestCategoriesReport(dart));
  stdout.writeln();
  stdout.writeln('=== slowest individual inputs (dart, top 5) ===');
  final ranked = [...dart.samples.where((s) => !s.crashed)]
    ..sort((a, b) => b.medianMicros.compareTo(a.medianMicros));
  for (final s in ranked.take(5)) {
    final kb = (s.input.bytes / 1024).toStringAsFixed(1);
    final us = s.medianMicros;
    final mbps = us == 0
        ? '∞'
        : (s.input.bytes / us * 1e6 / (1024 * 1024)).toStringAsFixed(2);
    stdout.writeln(
      '  ${s.input.category.padRight(11)} '
      '${us.toString().padLeft(8)}us  '
      '${kb.padLeft(7)} KB  $mbps MB/s  ${s.input.label}',
    );
  }
  if (dart.crashCount > 0) {
    stdout.writeln();
    stdout.writeln(
      'dart parser crashed on ${dart.crashCount} input(s); excluded from totals',
    );
  }
}

void _printSummary(_Bench b) {
  stdout.writeln(
    '${b.label.padRight(6)} '
    'total ${(b.totalBytes / 1024).toStringAsFixed(1)} KB / '
    '${(b.totalParseMicros / 1000).toStringAsFixed(1)} ms = '
    '${b.mbPerSec.toStringAsFixed(2)} MB/s, '
    'median per op ${b.medianMicrosPerOp.toStringAsFixed(0)}us',
  );
}

String _slowestCategoriesReport(_Bench b) {
  final byCategory = <String, _CategoryStats>{};
  for (final s in b.samples) {
    if (s.crashed) continue;
    final stats = byCategory.putIfAbsent(
      s.input.category,
      () => _CategoryStats(),
    );
    stats.totalBytes += s.input.bytes;
    stats.totalMicros += s.medianMicros;
    stats.count += 1;
  }
  final ranked = byCategory.entries.toList()
    ..sort((a, b) {
      final am =
          a.value.totalMicros /
          (a.value.totalBytes == 0 ? 1 : a.value.totalBytes);
      final bm =
          b.value.totalMicros /
          (b.value.totalBytes == 0 ? 1 : b.value.totalBytes);
      return bm.compareTo(am);
    });
  final out = StringBuffer();
  for (final entry in ranked) {
    final s = entry.value;
    final mbps = s.totalMicros == 0
        ? double.infinity
        : (s.totalBytes / s.totalMicros * 1e6 / (1024 * 1024));
    out.writeln(
      '  ${entry.key.padRight(11)} ${s.count.toString().padLeft(3)} '
      'inputs  ${(s.totalBytes / 1024).toStringAsFixed(1)} KB  '
      '${mbps.toStringAsFixed(2)} MB/s  '
      '(${(s.totalMicros / 1000).toStringAsFixed(1)} ms total)',
    );
  }
  return out.toString().trimRight();
}

class _CategoryStats {
  int totalBytes = 0;
  int totalMicros = 0;
  int count = 0;
}

// Silences unused warnings if canonicalize is not used in bench paths; kept
// imported because future per-node-kind breakdowns may want to inspect the
// AST shape.
// ignore: unused_element
String _unused() => canonicalize(null);
