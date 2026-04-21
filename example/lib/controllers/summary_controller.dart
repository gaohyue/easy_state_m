import 'package:easy_state_m/easy_state_m.dart';

/// App-level controller that tracks the number of completed tasks.
///
/// Subscribes to the [TaskController] channel 'task_completed' via
/// [channelBindings]. Whenever a task is marked done on any TaskPage,
/// this controller receives the notification and updates the badge count.
///
/// This controller is never aware of TaskController's internal state —
/// it only reacts to messages on the named channel.
class SummaryController extends EasyController {
  int completedCount = 0;

  @override
  List<EasyChannelBinding> get channelBindings => [
        // Receives 'task_completed' messages emitted by TaskController.
        // The channel is scoped to SummaryController's runtime type, so it
        // never collides with same-named channels on other controllers.
        EasyChannelBinding<String>('task_completed', _onTaskCompleted),
      ];

  void _onTaskCompleted(String taskTitle) {
    completedCount++;
    refresh();
  }
}
