import 'package:easy_state_m/easy_state_m.dart';
import 'package:example/page_a/page_a_controller.dart';
import 'package:flutter/material.dart';

class PageA extends StatelessWidget {
  const PageA({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyScope(
      create: () => PageAController(),
      builder: (context, controller) {
        return Scaffold(
          body: ListView.builder(
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () {
                  controller.onTap(index);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      EasyConsumer<PageAController>(
                        id: "id$index",
                        builder: (context, controller) {
                          return Text(
                            "第$index行,count = ${controller.items[index].count}",
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            itemCount: controller.items.length,
          ),
        );
      },
    );
  }
}
