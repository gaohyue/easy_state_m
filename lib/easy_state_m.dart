import 'dart:async';
import 'package:flutter/widgets.dart';

/// ============================================================================
/// Easy State Framework
/// A lightweight, highly reactive, and decoupled state management micro-framework.
/// Designed for O(1) performance, multi-way data synchronization, and strict type safety.
/// ============================================================================

// -----------------------------------------------------------------------------
// Part 1: Domain Events & Bindings
// -----------------------------------------------------------------------------

/// The base contract for all domain events in the framework.
///
/// Events represent domain facts that have occurred. By declaring the
/// [targetController], the framework guarantees that the event is broadcasted
/// only to active instances of that specific controller type, naturally
/// supporting seamless multi-instance synchronization.
abstract class EasyEvent {
  /// Declares the target receiver type of this event.
  /// Must be a subclass of [EasyController].
  Type get targetController;
}

/// A configuration object that binds an [EasyEvent] to its handler function.
///
/// Uses generic constraint `<T>` to ensure absolute compile-time safety,
/// completely eliminating runtime type-casting overhead and exceptions.
class EasyEventBinding<T extends EasyEvent> {
  /// The callback function executed when the event is intercepted.
  final void Function(T event) handler;

  /// Creates a new event binding.
  const EasyEventBinding(this.handler);

  /// Extracts the generic type for precise type matching and routing.
  Type get eventType => T;

  /// Encapsulates safe execution logic with anti-corruption type checking.
  ///
  /// Throws an assertion error if event polymorphism is detected.
  void execute(dynamic event) {
    assert(
      event.runtimeType == T,
      '[Easy State] Event Polymorphism is strictly forbidden.\n'
      'Expected exactly <$T>, but received <${event.runtimeType}>.\n'
      'Please ensure you bind the exact event class to avoid routing leaks.',
    );

    if (event is T) {
      handler(event);
    }
  }
}

// -----------------------------------------------------------------------------
// Part 2: Global Event Bus
// -----------------------------------------------------------------------------

/// The internal private event bus.
///
/// Handles the global broadcasting of [EasyEvent]s. This is completely
/// black-boxed from the public API to prevent architectural abuse.
class _EasyEventBus {
  static final StreamController<EasyEvent> _bus = StreamController.broadcast();

  /// Exposes the global event stream.
  static Stream<EasyEvent> get stream => _bus.stream;

  /// Broadcasts an event to all active listeners.
  static void broadcast(EasyEvent event) {
    if (!_bus.isClosed) {
      _bus.add(event);
    }
  }

  /// Resets the internal bus. Used strictly for unit testing.
  // @visibleForTesting
  // static void reset() {
  //   _bus.close();
  //   _bus = StreamController<EasyEvent>.broadcast();
  // }
}

// -----------------------------------------------------------------------------
// Part 3: Core Controller
// -----------------------------------------------------------------------------

/// The core logic hub and state container.
///
/// Subclass [EasyController] to manage your business logic, local state,
/// and declarative global event bindings.
abstract class EasyController {
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// Whether this controller has been permanently disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the [initialize] lifecycle hook has been executed.
  bool get isInitialized => _isInitialized;

  // --- Global Event Broadcasting API ---

  /// Broadcasts a domain [event] globally to the system.
  ///
  /// The underlying layer will accurately route it to ALL living instances
  /// of the target controller, enabling seamless multi-way data synchronization.
  static void broadcast(EasyEvent event) => _EasyEventBus.broadcast(event);

  // --- Local UI Driver ---

  final StreamController<List<String>?> _refreshController =
      StreamController<List<String>?>.broadcast();

  /// Exposes the refresh stream for [EasyConsumer]s to listen to.
  Stream<List<String>?> get refreshStream => _refreshController.stream;

  /// Triggers local UI rebuilds for consumers attached to this controller.
  ///
  /// * `refresh()`: Fully refreshes all consumers under the current scope.
  /// * `refresh(ids: ['header'])`: Accurately triggers rebuilds for consumers with the matching ID.
  /// * `refresh(ids: [])`: Silent operation. Does not trigger any rebuild.
  @protected
  void refresh({List<String>? ids}) {
    if (_isDisposed || _refreshController.isClosed) return;
    _refreshController.add(ids);
  }

  // --- Declarative Event Routing ---

  StreamSubscription<EasyEvent>? _busSubscription;
  final Map<Type, EasyEventBinding> _bindingsMap = {};

  /// Declarative event configuration table.
  ///
  /// Subclasses must override this property to provide the events and handlers
  /// this controller needs to listen to.
  @protected
  List<EasyEventBinding> get eventBindings => [];

  // --- Lifecycle Hooks ---

  /// Initialization hook. Automatically called by [EasyScope].
  @mustCallSuper
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    for (final binding in eventBindings) {
      assert(
        binding.eventType != EasyEvent && binding.eventType != dynamic,
        '[Easy State] Type Erasure Detected in $runtimeType.\n'
        'You must explicitly specify the generic type for EasyEventBinding.\n'
        'Correct usage: EasyEventBinding<MyEvent>(_onEvent).',
      );
      _bindingsMap[binding.eventType] = binding;
    }

    if (_bindingsMap.isNotEmpty) {
      _busSubscription = _EasyEventBus.stream
          .where((event) => event.targetController == runtimeType)
          .listen(
            (event) {
              try {
                _bindingsMap[event.runtimeType]?.execute(event);
              } catch (e, stackTrace) {
                // Business Exception Isolation: Prevents a faulty handler from crashing the broadcast stream.
                debugPrint(
                  '[$runtimeType] Event Execution Error: $e\n$stackTrace',
                );
              }
            },
            onError: (error, stackTrace) {
              debugPrint('[$runtimeType] Stream Error: $error\n$stackTrace');
            },
          );
    }
  }

  /// Disposal hook. Automatically called by [EasyScope] when unmounted.
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _bindingsMap.clear();
    _busSubscription?.cancel();
    _refreshController.close();
  }
}

// -----------------------------------------------------------------------------
// Part 4: Scope & Dependency Injection
// -----------------------------------------------------------------------------

/// Internal InheritedWidget used for O(1) context lookups.
class _EasyInheritedScope<T extends EasyController> extends InheritedWidget {
  final T controller;

  const _EasyInheritedScope({required this.controller, required super.child});

  @override
  bool updateShouldNotify(_EasyInheritedScope<T> oldWidget) {
    return oldWidget.controller != controller;
  }
}

/// Builder signature for [EasyScope].
typedef EasyScopeBuilder<T extends EasyController> =
    Widget Function(BuildContext context, T controller);

/// A dependency injection container and lifecycle manager for [EasyController].
class EasyScope<T extends EasyController> extends StatefulWidget {
  final T Function()? _create;
  final T? _value;
  final EasyScopeBuilder<T> builder;
  final bool _isShared;

  /// [Standard Mode]: Lazily creates the controller and manages its lifecycle.
  ///
  /// The [create] closure protects the state from being wiped out during Flutter Hot Reload.
  const EasyScope({
    required T Function() create,
    required this.builder,
    super.key,
  }) : _create = create,
       _value = null,
       _isShared = false;

  /// [Shared Mode]: Injects an existing controller instance without interfering with its lifecycle.
  ///
  /// Useful for cross-route state relay or providing global singletons.
  const EasyScope.value({required T value, required this.builder, super.key})
    : _value = value,
      _create = null,
      _isShared = true;

  /// Safely looks up the controller instance. Returns `null` if not found.
  static T? maybeOf<T extends EasyController>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_EasyInheritedScope<T>>()
        ?.controller;
  }

  /// Strictly looks up the controller instance. Throws a [FlutterError] if not found.
  static T of<T extends EasyController>(BuildContext context) {
    final controller = maybeOf<T>(context);
    if (controller == null) {
      throw FlutterError.fromParts([
        ErrorSummary('[Easy State] Context Lookup Failed!'),
        ErrorDescription(
          'Could not find an instance of <$T> in the current context.',
        ),
        ErrorHint(
          'Please ensure:\n'
          '1. The widget calling EasyScope.of() is wrapped inside an EasyScope<$T>.\n'
          '2. You did not cross a Navigator barrier (pushed routes cannot find providers from previous routes unless shared).',
        ),
      ]);
    }
    return controller;
  }

  @override
  State<EasyScope<T>> createState() => _EasyScopeState<T>();
}

class _EasyScopeState<T extends EasyController> extends State<EasyScope<T>> {
  late T _controller;

  @override
  void initState() {
    super.initState();
    if (!widget._isShared) {
      _controller = widget._create!();
      _controller.initialize();
    } else {
      _controller = widget._value!;
      assert(
        _controller.isInitialized,
        '[Easy State] Uninitialized Shared Instance Detected.\n'
        'You injected <$T> using EasyScope.value, but its initialize() was never called.\n'
        'If this is a global singleton, ensure you manually call .initialize() during its registration.',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Guardrail: Strictly forbid nesting EasyScopes of the exact same Controller type.
    assert(() {
      final ancestor = context
          .dependOnInheritedWidgetOfExactType<_EasyInheritedScope<T>>();
      if (ancestor != null && ancestor.controller != _controller) {
        throw FlutterError.fromParts([
          ErrorSummary(
            '[Easy State] Fatal Architectural Error: Nested Scopes Detected!',
          ),
          ErrorDescription(
            'You nested two <$T> Scopes in the same Widget tree.',
          ),
          ErrorHint(
            'Due to Flutter\'s InheritedWidget lookup mechanism, the inner Scope will completely '
            'shadow the outer Scope, causing broken data flows and ghost states.\n\n'
            'Solutions:\n'
            '1. Ensure similar modules are sibling nodes, not nested.\n'
            '2. If nesting is absolutely required, create a distinct subclass (e.g., class Inner$T extends $T) '
            'to provide a unique lookup Type.',
          ),
        ]);
      }
      return true;
    }());
  }

  @override
  void didUpdateWidget(covariant EasyScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._isShared && widget._value != oldWidget._value) {
      _controller = widget._value!;
      assert(
        _controller.isInitialized,
        '[Easy State] Swapped shared instance is uninitialized.',
      );
    }
  }

  @override
  void dispose() {
    if (!widget._isShared) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EasyInheritedScope<T>(
      controller: _controller,
      child: Builder(builder: (ctx) => widget.builder(ctx, _controller)),
    );
  }
}

// -----------------------------------------------------------------------------
// Part 5: Local State Consumer
// -----------------------------------------------------------------------------

/// Builder signature for [EasyConsumer].
typedef EasyConsumerBuilder<T extends EasyController> =
    Widget Function(BuildContext context, T controller);

/// A reactive UI widget that listens to [EasyController.refreshStream] for precise rebuilds.
class EasyConsumer<T extends EasyController> extends StatefulWidget {
  /// Local refresh identifier.
  /// If null, this consumer responds to the controller's full refresh commands.
  final String? id;

  /// The widget builder triggered upon state changes.
  final EasyConsumerBuilder<T> builder;

  const EasyConsumer({required this.builder, this.id, super.key});

  @override
  State<EasyConsumer<T>> createState() => _EasyConsumerState<T>();
}

class _EasyConsumerState<T extends EasyController>
    extends State<EasyConsumer<T>> {
  T? _controller;
  StreamSubscription<List<String>?>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant EasyConsumer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.id != oldWidget.id) {
      _subscribeIfNeeded();
    }
  }

  void _subscribeIfNeeded() {
    final newController = EasyScope.maybeOf<T>(context);

    // Re-subscribe only when the underlying memory address of the Controller changes.
    if (_controller != newController) {
      _subscription?.cancel();
      _controller = newController;

      if (_controller != null && !_controller!.isDisposed) {
        _subscription = _controller!.refreshStream.listen(
          (updateIds) {
            if (!mounted) return;

            if (updateIds == null) {
              setState(() {});
            } else if (widget.id != null && updateIds.contains(widget.id)) {
              setState(() {});
            }
          },
          onError: (e, stack) {
            debugPrint('[Easy State] EasyConsumer<$T> Stream Error: $e');
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      throw FlutterError.fromParts([
        ErrorSummary('[Easy State] EasyConsumer Mount Failed!'),
        ErrorDescription('EasyConsumer<$T> could not locate its controller.'),
        ErrorHint(
          'Ensure that this EasyConsumer is wrapped inside an EasyScope<$T>.',
        ),
      ]);
    }
    // Synchronous read of memory data eliminates first-frame white screens.
    return widget.builder(context, _controller!);
  }
}
