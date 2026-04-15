import 'package:easy_state/easy_state_m.dart';
import 'package:example/controllers/summary_controller.dart';
import 'package:example/pages/home_page.dart';
import 'package:flutter/material.dart';

void main() {
  // Initialize the app-level controller before runApp so it is ready
  // to receive channel messages as soon as any TaskPage is opened.
  final summaryController = SummaryController()..initialize();

  runApp(MyApp(summaryController: summaryController));
}

class MyApp extends StatelessWidget {
  final SummaryController summaryController;

  const MyApp({required this.summaryController, super.key});

  @override
  Widget build(BuildContext context) {
    // EasyMultiScope nests all app-level scopes without deep indentation.
    // SummaryController is shared (externally managed), so EasyScope.value
    // is used — the scope does NOT dispose it on unmount.
    //
    // Add more app-level controllers here as EasyScopeProvide entries.
    return EasyMultiScope(
      entries: [
        EasyScopeProvide.value(value: summaryController),
      ],
      child: MaterialApp(
        title: 'Easy State Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
