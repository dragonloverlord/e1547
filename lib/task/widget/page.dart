import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sub/flutter_sub.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TasksController controller = context.read<TasksController>();
    return TasksListProvider(
      child: Consumer<TasksListController>(
        builder: (context, listController, _) => _SuppressBubbleWhileMounted(
          controller: controller,
          child: SelectionLayout<Task>(
            items: listController.items ?? const [],
            child: AdaptiveScaffold(
              appBar: SelectionAppBar<Task>(
                titleBuilder: (context, layoutData) =>
                    Text('${layoutData.selections.length} selected'),
                actionBuilder: (context, layoutData) =>
                    taskBulkActions(controller, layoutData),
                child: DefaultAppBar(
                  title: const Text('Tasks'),
                  actions: [
                    IconButton(
                      tooltip: 'clear all',
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: controller.clearAll,
                    ),
                  ],
                ),
              ),
              drawer: const RouterDrawer(),
              body: const CustomScrollView(
                primary: true,
                slivers: [SliverTasksList()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuppressBubbleWhileMounted extends StatelessWidget {
  const _SuppressBubbleWhileMounted({
    required this.controller,
    required this.child,
  });

  final TasksController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SubEffect(
      effect: () {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.suppressBubble.value = true,
        );
        return () => WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.suppressBubble.value = false,
        );
      },
      keys: [controller],
      child: child,
    );
  }
}
