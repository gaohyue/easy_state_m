import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/controllers/summary_controller.dart';
import 'package:example/models/task.dart';

/// Page-scoped controller that manages the task list.
///
/// When a task is marked as done, it:
///   1. Updates local state and triggers a targeted refresh for that row only.
///   2. Emits a 'task_completed' message to [SummaryController] via channel,
///      so the app-level badge updates without any direct coupling.
class TaskController extends EasyController {
  List<Task> tasks = [];

  @override
  void initialize() {
    super.initialize();
    tasks = [
      Task('Buy groceries'),
      Task('Read 20 pages'),
      Task('Go for a walk'),
      Task('Write unit tests'),
      Task('Review pull request'),
    ];
  }

  /// Marks the task at [index] as done.
  ///
  /// Uses [refresh] with a targeted id so only the affected row rebuilds,
  /// leaving all other rows untouched.
  void completeTask(int index) {
    if (tasks[index].isDone) return;
    tasks[index].isDone = true;

    // Targeted refresh — only the row widget with id 'task_$index' rebuilds.
    refresh(ids: ['task_$index']);

    // Notify SummaryController via channel. No import of SummaryController's
    // internal state — just a typed message on a named channel.
    emit<SummaryController>('task_completed', tasks[index].title);
  }
}
