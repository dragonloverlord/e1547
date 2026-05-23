import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';
import 'package:flutter/material.dart';

List<Widget> taskBulkActions(
  TasksController controller,
  SelectionLayoutData<Task> layoutData,
) {
  final Set<Task> selected = layoutData.selections;
  final bool hasActive = selected.any(
    (t) => t.status == TaskStatus.pending || t.status == TaskStatus.running,
  );
  final bool hasRetryable = selected.any(
    (t) => t.status == TaskStatus.failed || t.status == TaskStatus.canceled,
  );
  final bool hasTerminal = selected.any(
    (t) =>
        t.status == TaskStatus.completed ||
        t.status == TaskStatus.failed ||
        t.status == TaskStatus.canceled,
  );
  return [
    if (hasActive)
      IconButton(
        tooltip: 'cancel',
        icon: const Icon(Icons.block),
        onPressed: () async {
          for (final t in selected) {
            if (t.status == TaskStatus.pending ||
                t.status == TaskStatus.running) {
              await controller.cancel(t.id);
            }
          }
          layoutData.clear();
        },
      ),
    if (hasRetryable)
      IconButton(
        tooltip: 'retry',
        icon: const Icon(Icons.refresh),
        onPressed: () async {
          for (final t in selected) {
            if (t.status == TaskStatus.failed ||
                t.status == TaskStatus.canceled) {
              await controller.retry(t.id);
            }
          }
          layoutData.clear();
        },
      ),
    if (hasTerminal)
      IconButton(
        tooltip: 'dismiss',
        icon: const Icon(Icons.clear_all),
        onPressed: () async {
          for (final t in selected) {
            if (t.status == TaskStatus.completed ||
                t.status == TaskStatus.failed ||
                t.status == TaskStatus.canceled) {
              await controller.dismiss(t.id);
            }
          }
          layoutData.clear();
        },
      ),
  ];
}
