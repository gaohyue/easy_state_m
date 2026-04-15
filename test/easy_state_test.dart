import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_state_m/easy_state_m.dart';

// =============================================================================
// Test controllers
// =============================================================================

class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh();
  }

  void incrementById(String id) {
    count++;
    refresh(ids: [id]);
  }

  /// Exposes [refresh] with debounce to the test without violating @protected.
  void rapidUpdate(int value, Duration debounce) {
    count = value;
    refresh(debounce: debounce);
  }
}

/// Receives messages on channel 'ping' (int payload).
class ReceiverA extends EasyController {
  final List<int> log = [];

  @override
  List<EasyChannelBinding> get channelBindings => [
        EasyChannelBinding<int>('ping', log.add),
      ];
}

/// Same channel name as [ReceiverA] but a distinct type — used for isolation tests.
class ReceiverB extends EasyController {
  final List<int> log = [];

  @override
  List<EasyChannelBinding> get channelBindings => [
        EasyChannelBinding<int>('ping', log.add),
      ];
}

class Sender extends EasyController {
  void pingA(int v) => emit<ReceiverA>('ping', v);
  void pingB(int v) => emit<ReceiverB>('ping', v);
}

/// Used to verify that [emit] with the base [EasyController] type triggers an
/// [AssertionError].
class TypeErasureSender extends EasyController {
  void sendWithBaseType() => emit<EasyController>('any', null);
}

/// Spy [EasyChannelBus] that records every [emit] call.
class _SpyBus implements EasyChannelBus {
  final List<String> emitLog = [];

  @override
  void listen(Type ct, String ch, void Function(dynamic) h) {}

  @override
  void cancel(Type ct, String ch, void Function(dynamic) h) {}

  @override
  void emit(Type t, String ch, dynamic d) => emitLog.add('$t/$ch/$d');

  @override
  void dispose() {}
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // Reset the channel bus after every test to prevent cross-test pollution.
  tearDown(EasyChannel.reset);

  // ---------------------------------------------------------------------------
  // EasyController — lifecycle
  // ---------------------------------------------------------------------------

  group('EasyController — lifecycle', () {
    test('initialize() sets isInitialized to true', () {
      final c = CounterController();
      expect(c.isInitialized, isFalse);
      c.initialize();
      expect(c.isInitialized, isTrue);
      c.dispose();
    });

    test('initialize() is idempotent — channel bindings registered only once', () {
      final recv = ReceiverA()..initialize();
      final send = Sender()..initialize();

      recv.initialize(); // second call must be a no-op

      send.pingA(1);
      expect(recv.log, [1],
          reason: 'Handler must fire exactly once, not twice.');

      recv.dispose();
      send.dispose();
    });

    test('dispose() sets isDisposed to true', () {
      final c = CounterController()..initialize();
      c.dispose();
      expect(c.isDisposed, isTrue);
    });

    test('dispose() is idempotent', () {
      final c = CounterController()..initialize();
      c.dispose();
      expect(() => c.dispose(), returnsNormally);
    });

    test('refresh() after dispose() is silently ignored', () {
      final c = CounterController()..initialize()..dispose();
      expect(() => c.increment(), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // EasyController — channel messaging
  // ---------------------------------------------------------------------------

  group('EasyController — channel messaging', () {
    test('emit<C> delivers the message to the matching controller type', () {
      final recv = ReceiverA()..initialize();
      final send = Sender()..initialize();

      send.pingA(42);
      expect(recv.log, [42]);

      recv.dispose();
      send.dispose();
    });

    test('same channel name is isolated by controller type', () {
      final a = ReceiverA()..initialize();
      final b = ReceiverB()..initialize();
      final send = Sender()..initialize();

      send.pingA(7); // targets ReceiverA only
      expect(a.log, [7]);
      expect(b.log, isEmpty, reason: 'ReceiverB must not receive a ReceiverA message.');

      send.pingB(3); // targets ReceiverB only
      expect(b.log, [3]);
      expect(a.log, [7], reason: 'ReceiverA must not receive a ReceiverB message.');

      a.dispose();
      b.dispose();
      send.dispose();
    });

    test('disposed controller no longer receives messages', () {
      final recv = ReceiverA()..initialize();
      final send = Sender()..initialize();

      recv.dispose(); // unregisters channel binding
      send.pingA(99);

      expect(recv.log, isEmpty);
      send.dispose();
    });

    test('multiple instances of the same type all receive the message', () {
      final r1 = ReceiverA()..initialize();
      final r2 = ReceiverA()..initialize();
      final send = Sender()..initialize();

      send.pingA(5);
      expect(r1.log, [5]);
      expect(r2.log, [5]);

      r1.dispose();
      r2.dispose();
      send.dispose();
    });

    test('messages arrive in emission order', () {
      final recv = ReceiverA()..initialize();
      final send = Sender()..initialize();

      send.pingA(1);
      send.pingA(2);
      send.pingA(3);
      expect(recv.log, [1, 2, 3]);

      recv.dispose();
      send.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // EasyChannel — test injection
  // ---------------------------------------------------------------------------

  group('EasyChannel — test injection', () {
    test('override() routes through the spy bus', () {
      final spy = _SpyBus();
      EasyChannel.override(spy);

      final send = Sender()..initialize();
      send.pingA(1);

      expect(spy.emitLog, contains('$ReceiverA/ping/1'));
      send.dispose();
    });

    test('reset() restores the default bus after override', () {
      EasyChannel.override(_SpyBus());
      EasyChannel.reset();

      // After reset, real message delivery must work normally.
      final recv = ReceiverA()..initialize();
      final send = Sender()..initialize();

      send.pingA(9);
      expect(recv.log, [9]);

      recv.dispose();
      send.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // EasyScope & EasyConsumer — widget layer
  // ---------------------------------------------------------------------------

  group('EasyScope & EasyConsumer — widget layer', () {
    testWidgets('owned scope: consumer rebuilds on full refresh', (tester) async {
      late CounterController ctrl;

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>(
          create: () => CounterController(),
          builder: (context, c) {
            ctrl = c;
            return EasyConsumer<CounterController>(
              builder: (_, c) => Text('${c.count}'),
            );
          },
        ),
      ));

      expect(find.text('0'), findsOneWidget);

      ctrl.increment();
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets(
        'targeted refresh: only the consumer with the matching id rebuilds',
        (tester) async {
      var fullRebuildCount = 0;
      var targetedRebuildCount = 0;
      late CounterController ctrl;

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>(
          create: () => CounterController(),
          builder: (context, c) {
            ctrl = c;
            return Column(children: [
              EasyConsumer<CounterController>(
                builder: (_, c) {
                  fullRebuildCount++;
                  return Text('full:${c.count}');
                },
              ),
              EasyConsumer<CounterController>(
                id: 'target',
                builder: (_, c) {
                  targetedRebuildCount++;
                  return Text('targeted:${c.count}');
                },
              ),
            ]);
          },
        ),
      ));

      // Reset counters after the initial build pass.
      fullRebuildCount = 0;
      targetedRebuildCount = 0;

      ctrl.incrementById('target');
      await tester.pump();

      expect(targetedRebuildCount, 1,
          reason: "Consumer with id 'target' must rebuild.");
      expect(fullRebuildCount, 0,
          reason: 'Unrelated consumer must NOT rebuild.');
    });

    testWidgets('debounce: coalesces rapid calls into exactly one rebuild',
        (tester) async {
      var rebuildCount = 0;
      late CounterController ctrl;
      const debounce = Duration(milliseconds: 50);

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>(
          create: () => CounterController(),
          builder: (context, c) {
            ctrl = c;
            return EasyConsumer<CounterController>(
              builder: (_, c) {
                rebuildCount++;
                return Text('${c.count}');
              },
            );
          },
        ),
      ));

      rebuildCount = 0;

      // Fire three rapid updates within the debounce window.
      ctrl.rapidUpdate(10, debounce);
      ctrl.rapidUpdate(20, debounce);
      ctrl.rapidUpdate(30, debounce);

      // Still inside the debounce window — no rebuild yet.
      await tester.pump(const Duration(milliseconds: 20));
      expect(rebuildCount, 0,
          reason: 'No rebuild should occur while debounce is active.');

      // Debounce window has expired — exactly one rebuild.
      await tester.pump(const Duration(milliseconds: 60));
      expect(rebuildCount, 1,
          reason: 'Exactly one rebuild after debounce elapses.');
      expect(find.text('30'), findsOneWidget,
          reason: 'Final value (30) must be rendered.');
    });

    testWidgets('owned scope: controller is disposed when the scope unmounts',
        (tester) async {
      late CounterController ctrl;

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>(
          create: () => CounterController(),
          builder: (_, c) {
            ctrl = c;
            return const SizedBox();
          },
        ),
      ));

      expect(ctrl.isDisposed, isFalse);

      // Unmount the scope by replacing the widget tree.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(ctrl.isDisposed, isTrue);
    });

    testWidgets(
        'shared scope: controller is NOT disposed when the scope unmounts',
        (tester) async {
      final shared = CounterController()..initialize();

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>.value(
          value: shared,
          child: const SizedBox(),
        ),
      ));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(shared.isDisposed, isFalse,
          reason: 'Shared controller lifecycle is managed externally.');
      shared.dispose();
    });

    testWidgets('EasyScope.of() throws a descriptive FlutterError when missing',
        (tester) async {
      late BuildContext ctx;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      expect(
        () => EasyScope.of<CounterController>(ctx),
        throwsA(isA<FlutterError>()),
      );
    });

    testWidgets('EasyScope.maybeOf() returns null when no scope exists',
        (tester) async {
      late BuildContext ctx;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      expect(EasyScope.maybeOf<CounterController>(ctx), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // EasyMultiScope
  // ---------------------------------------------------------------------------

  group('EasyMultiScope', () {
    testWidgets('all entries are accessible to descendant widgets',
        (tester) async {
      CounterController? counter;
      ReceiverA? receiverA;

      await tester.pumpWidget(MaterialApp(
        home: EasyMultiScope(
          entries: [
            EasyScopeProvide(create: () => CounterController()),
            EasyScopeProvide(create: () => ReceiverA()),
          ],
          child: Builder(builder: (context) {
            counter = EasyScope.of<CounterController>(context);
            receiverA = EasyScope.of<ReceiverA>(context);
            return const SizedBox();
          }),
        ),
      ));

      expect(counter, isNotNull);
      expect(receiverA, isNotNull);
    });

    testWidgets(
        'entries are ordered outermost-first — index 0 is accessible to all',
        (tester) async {
      ReceiverB? foundFromInner;

      await tester.pumpWidget(MaterialApp(
        home: EasyMultiScope(
          entries: [
            EasyScopeProvide(create: () => ReceiverB()), // outermost (index 0)
            EasyScopeProvide(create: () => ReceiverA()), // inner (index 1)
          ],
          child: Builder(builder: (context) {
            // ReceiverB (outermost) must be visible from within ReceiverA's scope.
            foundFromInner = EasyScope.of<ReceiverB>(context);
            return const SizedBox();
          }),
        ),
      ));

      expect(foundFromInner, isNotNull);
    });

    testWidgets('shared entry does not dispose the controller on unmount',
        (tester) async {
      final shared = CounterController()..initialize();

      await tester.pumpWidget(MaterialApp(
        home: EasyMultiScope(
          entries: [EasyScopeProvide.value(value: shared)],
          child: const SizedBox(),
        ),
      ));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(shared.isDisposed, isFalse);
      shared.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Guardrails — debug assertions
  // ---------------------------------------------------------------------------

  group('Guardrails — debug assertions', () {
    testWidgets('nested same-type EasyScope throws a FlutterError',
        (tester) async {
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;

      await tester.pumpWidget(MaterialApp(
        home: EasyScope<CounterController>(
          create: () => CounterController(),
          builder: (ctx, c) => EasyScope<CounterController>(
            create: () => CounterController(),
            child: const SizedBox(),
          ),
        ),
      ));

      expect(errors, isNotEmpty);
      expect(errors.first.summary.toString(), contains('Nested EasyScope'));

      FlutterError.onError = FlutterError.presentError;
    });

    test('EasyChannelBinding without an explicit type arg throws AssertionError',
        () {
      // Passing a void Function(dynamic) forces T to be inferred as dynamic.
      expect(
        () => EasyChannelBinding('channel', (dynamic _) {}),
        throwsAssertionError,
      );
    });

    test('emit<EasyController> (base type) throws AssertionError', () {
      final sender = TypeErasureSender()..initialize();
      expect(() => sender.sendWithBaseType(), throwsAssertionError);
      sender.dispose();
    });
  });
}
