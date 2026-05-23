// Smoke test that proves the Dart -> Node -> dmark pipeline is wired
// correctly. Does NOT exercise this parser; only the bridge to dmark.
//
// Run with: flutter test test/markup/_bridge/bridge_smoke_test.dart
//
// Dev-only. Deleted in commit 2.

import 'package:flutter_test/flutter_test.dart';

import 'bridge.dart';
import '../conformance/_support/canonical.dart';

void main() {
  late DmarkBridge bridge;

  setUpAll(() async {
    bridge = await sharedDmarkBridge();
  });

  tearDownAll(() async {
    await disposeSharedDmarkBridge();
  });

  test('parses bold inline', () async {
    final ast = await bridge.parse('[b]hi[/b]');
    expect(
      canonicalize(ast),
      '{"children":[{"children":[{"children":[{"content":"hi","type":"text"}],"type":"bold"}],"type":"paragraph"}],"type":"document"}',
    );
  });

  test('parses empty input as empty document', () async {
    final ast = await bridge.parse('');
    expect(canonicalize(ast), '{"children":[],"type":"document"}');
  });

  test('caches identical inputs', () async {
    final a = await bridge.parse('h1. Hi\n');
    final b = await bridge.parse('h1. Hi\n');
    expect(identical(a, b), isTrue, reason: 'second call should return cached');
  });

  test('parses many inputs concurrently', () async {
    final inputs = List.generate(50, (i) => 'paragraph #$i with post #$i text');
    final results = await bridge.parseAll(inputs);
    expect(results.length, 50);
    for (final r in results) {
      final m = r as Map<String, dynamic>;
      expect(m['type'], 'document');
    }
  });

  test('canonicalize is order-stable across map insertion order', () async {
    final ast = await bridge.parse('[i]x[/i]') as Map<String, dynamic>;
    // Reverse the map insertion order in a clone and ensure canonical equal.
    Map<String, Object?> reverseKeys(Map<String, dynamic> m) {
      final keys = m.keys.toList().reversed.toList();
      return {
        for (final k in keys)
          k: m[k] is Map<String, dynamic>
              ? reverseKeys(m[k] as Map<String, dynamic>)
              : (m[k] is List
                    ? (m[k] as List)
                          .map(
                            (e) => e is Map<String, dynamic>
                                ? reverseKeys(e)
                                : e,
                          )
                          .toList()
                    : m[k]),
      };
    }

    final shuffled = reverseKeys(ast);
    expect(canonicalize(shuffled), canonicalize(ast));
  });
}
