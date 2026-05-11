import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/page_a/page_a_controller.dart';
import 'package:flutter/material.dart';

/// PageB shares the [PageAController] created by [PageA].
///
/// The controller is resolved from the inherited scope that PageA wraps
/// around this route during navigation — there is **no** controller passed
/// through the widget constructor. Tapping a row here mutates the same
/// state as PageA, so reopening PageA shows the updated counts.
class PageB extends StatelessWidget {
  const PageB({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyScope<PageAController>.share(
      value: EasyScope.of<PageAController>(context),
      builder: (context, controller) {
        return Scaffold(
          appBar: AppBar(title: const Text('Page B — shared')),
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
