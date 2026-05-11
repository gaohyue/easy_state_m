import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/page_a/page_a_controller.dart';
import 'package:example/page_b/page_b.dart';
import 'package:flutter/material.dart';

/// PageA owns the [PageAController] for the shared-state demo.
///
/// Tapping a row increments that row's counter (targeted refresh via id).
/// The "Open B" action pushes [PageB] inside an [EasyScope.share] that
/// re-injects this page's controller into the new route — PageB inherits
/// the state without receiving anything through its constructor.
class PageA extends StatelessWidget {
  const PageA({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyScope<PageAController>.build(
      create: () => PageAController(),
      builder: (context, controller) {
        return Scaffold(
          appBar: AppBar(title: const Text('Page A — owner')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Open Page B'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                // Re-inject the controller across the Navigator barrier so
                // PageB can resolve it with `EasyScope.of` without taking
                // it through a constructor parameter.
                builder: (_) => EasyScope<PageAController>.share(
                  value: controller,
                  builder: (_, _) => const PageB(),
                ),
              ),
            ),
          ),
          body: ListView.builder(
            itemCount: controller.items.length,
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () => controller.onTap(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: EasyConsumer<PageAController>(
                    id: 'id$index',
                    builder: (context, c) => Text(
                      'Row $index — count = ${c.items[index].count}',
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
