import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_state/easy_state.dart'; // 替换为你的实际包名

// =============================================================================
// 1. 准备测试桩 (Test Mocks)
// =============================================================================

class IncrementEvent extends EasyEvent {
  @override
  Type get targetController => CounterController;
  final int amount;
  IncrementEvent(this.amount);
}

class InvalidEvent extends EasyEvent {
  @override
  Type get targetController => CounterController;
}

class CounterController extends EasyController {
  int count = 0;

  @override
  List<EasyEventBinding> get eventBindings => [
    EasyEventBinding<IncrementEvent>((event) {
      count += event.amount;
      refresh(ids: ['count_text']);
    }),
  ];
}

void main() {
  // 每次测试前，重置底层的事件总线，防止测试用例之间互相污染
  setUp(() {
    // 注意：你需要在 _EasyEventBus 中把 reset() 暴露给 @visibleForTesting
    // _EasyEventBus.reset();
  });

  group('EasyController Logic Tests (逻辑层测试)', () {
    test('控制器初始化与全局事件广播测试', () async {
      final controller = CounterController();
      controller.initialize();

      expect(controller.count, 0);

      // 模拟全局发送事件
      EasyController.broadcast(IncrementEvent(5));

      // 等待微任务队列执行完毕 (Stream 是异步的)
      await Future.delayed(Duration.zero);

      expect(controller.count, 5);

      controller.dispose();
    });
  });

  group('EasyScope & EasyConsumer Widget Tests (UI 层测试)', () {
    testWidgets('标准模式：组件挂载与精准局部刷新', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EasyScope<CounterController>(
            create: () => CounterController(),
            builder: (context, controller) {
              return Scaffold(
                body: EasyConsumer<CounterController>(
                  id: 'count_text',
                  builder: (context, ctrl) {
                    return Text('Count: ${ctrl.count}');
                  },
                ),
              );
            },
          ),
        ),
      );

      // 验证初始状态
      expect(find.text('Count: 0'), findsOneWidget);

      // 触发全局事件
      EasyController.broadcast(IncrementEvent(10));
      await tester.pumpAndSettle(); // 等待 UI 重绘完毕

      // 验证 UI 是否成功响应刷新
      expect(find.text('Count: 10'), findsOneWidget);
    });

    testWidgets('共享模式：生命周期不被组件树销毁', (WidgetTester tester) async {
      // 1. 外部手动创建并初始化（模拟 GetIt 注入）
      final globalController = CounterController()..initialize();

      // 2. 挂载到 Widget 树
      await tester.pumpWidget(
        MaterialApp(
          home: EasyScope<CounterController>.value(
            value: globalController,
            builder: (context, controller) => Container(),
          ),
        ),
      );

      // 3. 将 Widget 树替换掉（模拟页面 Pop 销毁）
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // 4. 验证控制器依然存活（isDisposed 必须为 false）
      expect(globalController.isDisposed, isFalse);

      // 测试完毕手动销毁清理内存
      globalController.dispose();
    });
  });

  group('Guardrails Tests (架构护栏/防呆断言测试)', () {
    testWidgets('防线拦截：严禁同类 Scope 嵌套', (WidgetTester tester) async {
      // 捕获 Flutter 异常
      FlutterErrorDetails? errorDetails;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      await tester.pumpWidget(
        MaterialApp(
          // 外层 Scope
          home: EasyScope<CounterController>(
            create: () => CounterController(),
            builder: (context, controller) {
              // 内层 Scope (故意嵌套同类型，触发报错)
              return EasyScope<CounterController>(
                create: () => CounterController(),
                builder: (ctx, ctrl) => Container(),
              );
            },
          ),
        ),
      );

      // 验证是否成功拦截并抛出架构错误
      expect(errorDetails, isNotNull);
      expect(
        errorDetails!.summary.toString(),
        contains('Fatal Architectural Error: Nested Scopes Detected!'),
      );
    });
  });
}
