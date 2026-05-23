// Unit tests for the deep AST differ. The differ is order-insensitive on
// map keys (because diffs operate on canonical trees) but order-sensitive
// on list positions, which mirrors how AST children are positional.
//
// Dev-only. Deleted in commit 2.

import 'package:flutter_test/flutter_test.dart';

import 'diff.dart';

void main() {
  group('diffAst', () {
    test('equal trees return null', () {
      final a = {'type': 'document', 'children': []};
      final b = {'children': [], 'type': 'document'};
      expect(diffAst(a, b), isNull);
    });

    test('scalar mismatch reports leaf path', () {
      final d = diffAst(
        {'type': 'header', 'level': 1},
        {'type': 'header', 'level': 2},
      );
      expect(d, isNotNull);
      expect(d!.path, '/level');
      expect(d.expected, 1);
      expect(d.actual, 2);
    });

    test('missing key on one side reports that key', () {
      final d = diffAst(
        {'type': 'paragraph', 'children': []},
        {'type': 'paragraph'},
      );
      expect(d, isNotNull);
      expect(d!.path, '/children');
      expect(d.expected, isList);
      expect(d.actual, isNull);
    });

    test('list length mismatch reports the boundary index', () {
      final d = diffAst(
        {
          'type': 'document',
          'children': [
            {'type': 'paragraph'},
            {'type': 'paragraph'},
          ],
        },
        {
          'type': 'document',
          'children': [
            {'type': 'paragraph'},
          ],
        },
      );
      expect(d, isNotNull);
      expect(d!.path, '/children/1');
      expect(d.actual, isNull);
    });

    test('deeply nested first-difference is surfaced', () {
      final d = diffAst(
        {
          'type': 'document',
          'children': [
            {
              'type': 'paragraph',
              'children': [
                {'type': 'text', 'content': 'a'},
                {'type': 'text', 'content': 'b'},
              ],
            },
          ],
        },
        {
          'type': 'document',
          'children': [
            {
              'type': 'paragraph',
              'children': [
                {'type': 'text', 'content': 'a'},
                {'type': 'text', 'content': 'X'},
              ],
            },
          ],
        },
      );
      expect(d, isNotNull);
      expect(d!.path, '/children/0/children/1/content');
      expect(d.expected, 'b');
      expect(d.actual, 'X');
    });

    test('oneLineDiff truncates long values', () {
      final long = 'x' * 200;
      final d = diffAst({'v': long}, {'v': 'short'})!;
      final line = oneLineDiff(d, maxValueLen: 30);
      expect(line.length, lessThan(120));
      expect(line, contains('/v'));
    });
  });
}
