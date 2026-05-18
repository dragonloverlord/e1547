// Deep AST diff with smallest-path output.
//
// Given two canonical trees (Map / List / scalar) returns either `null`
// (trees are equal) or a [Diff] describing the deepest single point of
// divergence: the JSON-pointer-like path into the tree, the expected
// value (from the dmark proxy oracle), and the actual value (from this
// parser). A failing fixture emits one line: "at
// /children/0/children/2/type expected 'bold' got 'italic'".

import 'dart:convert';

import '../conformance/_support/canonical.dart';

class Diff {
  Diff({required this.path, required this.expected, required this.actual});

  /// JSON-pointer style path from the document root to the mismatch, using
  /// `/` separators and `0`-based list indices. Empty string means the roots
  /// themselves diverge in kind (e.g. one is a list, the other a map).
  final String path;

  /// The expected value at that path (frozen output from the dmark proxy
  /// oracle). Will be `null` if the path does not exist on the expected
  /// side (i.e. this parser produced an extra node).
  final Object? expected;

  /// The Dart parser value at that path. Will be `null` if the path does
  /// not exist on the Dart side (i.e. the Dart parser is missing a node).
  final Object? actual;

  /// True when one side is missing the path entirely.
  bool get isMissing => expected == null || actual == null;

  @override
  String toString() {
    final exp = const JsonEncoder.withIndent('  ').convert(expected);
    final act = const JsonEncoder.withIndent('  ').convert(actual);
    return 'diff at ${path.isEmpty ? "<root>" : path}\n'
        '  expected (dmark):\n${_indent(exp, 4)}\n'
        '  actual   (dart):\n${_indent(act, 4)}';
  }
}

/// Compare two AST trees. Both are expected to already have been passed
/// through [canonicalTree], but we re-canonicalize defensively because the
/// cost is small relative to a `flutter test` run and the asymmetry is
/// otherwise easy to miss.
Diff? diffAst(Object? expected, Object? actual) =>
    _walk(canonicalTree(expected), canonicalTree(actual), '');

Diff? _walk(Object? expected, Object? actual, String path) {
  if (expected is Map && actual is Map) {
    final keys = <String>{
      ...expected.keys.map((k) => k.toString()),
      ...actual.keys.map((k) => k.toString()),
    }.toList()..sort();
    for (final k in keys) {
      final next = '$path/$k';
      final hasE = expected.containsKey(k);
      final hasA = actual.containsKey(k);
      if (!hasE || !hasA) {
        return Diff(
          path: next,
          expected: hasE ? expected[k] : null,
          actual: hasA ? actual[k] : null,
        );
      }
      final inner = _walk(expected[k], actual[k], next);
      if (inner != null) return inner;
    }
    return null;
  }
  if (expected is List && actual is List) {
    final shared = expected.length < actual.length
        ? expected.length
        : actual.length;
    for (var i = 0; i < shared; i++) {
      final inner = _walk(expected[i], actual[i], '$path/$i');
      if (inner != null) return inner;
    }
    if (expected.length != actual.length) {
      final i = shared;
      return Diff(
        path: '$path/$i',
        expected: i < expected.length ? expected[i] : null,
        actual: i < actual.length ? actual[i] : null,
      );
    }
    return null;
  }
  if (expected.runtimeType != actual.runtimeType || expected != actual) {
    return Diff(path: path, expected: expected, actual: actual);
  }
  return null;
}

/// Convenience that takes canonical JSON strings and returns the same diff.
Diff? diffCanonicalJson(String expected, String actual) {
  if (expected == actual) return null;
  return diffAst(json.decode(expected), json.decode(actual));
}

/// Format a diff as a single short line suitable for a failure report.
/// Truncates long values so the output stays readable.
String oneLineDiff(Diff d, {int maxValueLen = 80}) {
  String trim(String s) =>
      s.length <= maxValueLen ? s : '${s.substring(0, maxValueLen - 1)}…';
  final exp = trim(canonicalize(d.expected));
  final act = trim(canonicalize(d.actual));
  return '${d.path.isEmpty ? "<root>" : d.path}: expected=$exp actual=$act';
}

String _indent(String text, int spaces) {
  final pad = ' ' * spaces;
  return text.split('\n').map((l) => '$pad$l').join('\n');
}
