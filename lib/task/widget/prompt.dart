import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';
import 'package:flutter/material.dart';

Future<void> showTasksPrompt(BuildContext context) async {
  if (Theme.of(context).isDesktop) {
    return showTasksDialog(context);
  } else {
    return showTasksSheet(context);
  }
}

Future<void> showTasksSheet(BuildContext context) async =>
    showDefaultSlidingBottomSheet(
      context,
      null,
      parentBuilder: (context, sheet) => TasksListProvider(
        child: Consumer<TasksListController>(
          builder: (context, listController, _) => SelectionLayout<Task>(
            items: listController.items ?? const [],
            child: sheet,
          ),
        ),
      ),
      headerBuilder: (context, state) => Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            _PromptHeader(controller: context.read<TasksController>()),
          ],
        ),
      ),
      customBuilder: (context, controller, state) => Material(
        child: CustomScrollView(
          controller: controller,
          slivers: const [SliverTasksList()],
        ),
      ),
    );

Future<void> showTasksDialog(BuildContext context) =>
    showDialog(context: context, builder: (context) => const TasksDialog());

class TasksDialog extends StatelessWidget {
  const TasksDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return TasksListProvider(
      child: Consumer<TasksListController>(
        builder: (context, listController, _) => SelectionLayout<Task>(
          items: listController.items ?? const [],
          child: AlertDialog(
            titlePadding: EdgeInsets.zero,
            contentPadding: EdgeInsets.zero,
            title: _PromptHeader(controller: context.read<TasksController>()),
            content: const SizedBox(width: 600, child: TasksListView()),
          ),
        ),
      ),
    );
  }
}

class _PromptHeader extends StatelessWidget {
  const _PromptHeader({required this.controller});

  final TasksController controller;

  @override
  Widget build(BuildContext context) {
    final layoutData = SelectionLayout.of<Task>(context);
    final selecting = layoutData.selections.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: selecting
            ? _SelectionBar(
                key: const ValueKey('select'),
                layoutData: layoutData,
                controller: controller,
              )
            : _ClearAllBar(
                key: const ValueKey('clear'),
                controller: controller,
              ),
      ),
    );
  }
}

class _ClearAllBar extends StatelessWidget {
  const _ClearAllBar({super.key, required this.controller});

  final TasksController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: controller.clearAll,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('clear all'),
          ),
        ],
      ),
    ),
  );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    super.key,
    required this.layoutData,
    required this.controller,
  });

  final SelectionLayoutData<Task> layoutData;
  final TasksController controller;

  @override
  Widget build(BuildContext context) {
    final Set<Task> selected = layoutData.selections;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'clear selection',
              icon: const Icon(Icons.close),
              onPressed: layoutData.clear,
            ),
            Text(
              '${selected.length} selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'select all',
              icon: const Icon(Icons.select_all),
              onPressed: layoutData.selectAll,
            ),
            ...taskBulkActions(controller, layoutData),
          ],
        ),
      ),
    );
  }
}
