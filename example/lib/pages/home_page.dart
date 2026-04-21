import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/controllers/summary_controller.dart';
import 'package:example/pages/task_page.dart';
import 'package:flutter/material.dart';

/// Home page — shows the completed-task badge and navigates to [TaskPage].
///
/// [SummaryController] is provided at the app level (see main.dart), so this
/// page simply looks it up with [EasyScope.of] and subscribes with
/// [EasyConsumer]. No [EasyScope] is created here.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Easy State — Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Rebuilds whenever SummaryController.refresh() is called —
            // triggered by the 'task_completed' channel message from TaskController.
            EasyConsumer<SummaryController>(
              builder: (context, summary) => Column(
                children: [
                  Text(
                    '${summary.completedCount}',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tasks completed',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              icon: const Icon(Icons.checklist),
              label: const Text('Open Task List'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TaskPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
