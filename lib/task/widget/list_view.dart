import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';
import 'package:flutter/material.dart';

String _groupOf(Task task) =>
    task.status == TaskStatus.pending || task.status == TaskStatus.running
    ? 'active'
    : 'done';

int _groupComparator(String a, String b) =>
    a == 'active' ? -1 : (b == 'active' ? 1 : 0);

int _itemComparator(Task a, Task b) {
  if (_groupOf(a) == 'done') {
    final int byTime = b.createdAt.compareTo(a.createdAt);
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
  }
  final int byTime = a.createdAt.compareTo(b.createdAt);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}

class TasksListView extends StatelessWidget {
  const TasksListView({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomScrollView(slivers: [SliverTasksList()]);
}

class SliverTasksList extends StatelessWidget {
  const SliverTasksList({super.key});

  @override
  Widget build(BuildContext context) {
    final TasksListController controller = context.watch<TasksListController>();
    final SelectionLayoutData<Task> layoutData = SelectionLayout.of<Task>(
      context,
    );
    return PagedSliverGroupedListView<int, Task, String>(
      state: controller.state,
      fetchNextPage: controller.getNextPage,
      groupBy: _groupOf,
      groupComparator: _groupComparator,
      itemComparator: _itemComparator,
      groupSeparatorBuilder: (value) => TasksSectionHeader(value),
      builderDelegate: defaultPagedChildBuilderDelegate<Task>(
        onRetry: controller.getNextPage,
        onEmpty: const Text('No tasks'),
        onError: const Text('Failed to load tasks'),
        itemBuilder: (context, task, index) => TaskTile(
          task: task,
          controller: context.read<TasksController>(),
          layoutData: layoutData,
        ),
      ),
    );
  }
}

class TasksSectionHeader extends StatelessWidget {
  const TasksSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: scheme.primary),
      ),
    );
  }
}
