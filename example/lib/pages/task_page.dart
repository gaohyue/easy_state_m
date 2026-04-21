import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/controllers/task_controller.dart';
import 'package:flutter/material.dart';

/// Task list page — owned [EasyScope] creates and disposes [TaskController].
///
/// Each row uses [EasyConsumer] with a unique [id] so that completing one task
/// only rebuilds that single row, leaving all other rows untouched.
class TaskPage extends StatelessWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    // EasyScope owns the lifecycle: TaskController is initialized on mount
    // and disposed when the page is popped.
    return EasyScope<TaskController>(
      create: () => TaskController(),
      builder: (context, controller) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Task List'),
            // Shows total and remaining count — rebuilds only on full refresh.
            actions: [
              EasyConsumer<TaskController>(
                builder: (context, ctrl) {
                  final remaining =
                      ctrl.tasks.where((t) => !t.isDone).length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        '$remaining remaining',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView.builder(
            itemCount: controller.tasks.length,
            itemBuilder: (context, index) {
              // Targeted refresh: only this row rebuilds when
              // controller.completeTask(index) calls refresh(ids: ['task_$index']).
              return EasyConsumer<TaskController>(
                id: 'task_$index',
                builder: (context, ctrl) {
                  final task = ctrl.tasks[index];
                  return ListTile(
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        task.isDone
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: ValueKey(task.isDone),
                        color: task.isDone ? Colors.green : Colors.grey,
                      ),
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration:
                            task.isDone ? TextDecoration.lineThrough : null,
                        color: task.isDone ? Colors.grey : null,
                      ),
                    ),
                    onTap: () => ctrl.completeTask(index),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
