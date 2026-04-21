import 'package:easy_state_m/easy_state_m.dart';

class Item {
  int count;
  Item({required this.count});
}

class PageAController extends EasyController {
  List<Item> items = [];

  @override
  void initialize() {
    super.initialize();
    items = [
      Item(count: 0),
      Item(count: 1),
      Item(count: 2),
      Item(count: 3),
      Item(count: 4),
      Item(count: 5),
      Item(count: 6),
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  void onTap(int index) {
    items[index].count++;
    refresh(ids: ["id$index"]);
  }

  void loadMore() {}
}
