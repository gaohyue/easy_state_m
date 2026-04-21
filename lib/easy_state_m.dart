import 'dart:async';
import 'package:flutter/widgets.dart';

/// Easy State — a lightweight, performance-optimized state management library
/// for Flutter.
///
/// ## Core concepts
///
/// - [EasyController] — holds business logic and drives UI updates via
///   [EasyController.refresh]. Manages its own lifecycle through [EasyController.initialize]
///   and [EasyController.dispose].
/// - [EasyScope] — provides a controller to a widget subtree using Flutter's
///   `InheritedWidget` mechanism. Automatically calls [EasyController.initialize]
///   and [EasyController.dispose].
/// - [EasyConsumer] — a widget that rebuilds whenever [EasyController.refresh]
///   is called, without any `Stream` or `ChangeNotifier` overhead.
///
/// ## Cross-controller messaging
///
/// Controllers in sibling scopes communicate through typed, named channels.
/// Channels are namespaced by the target controller's runtime type, so the
/// same channel name used in different controllers never collides.
///
/// ```dart
/// // Emitter — inside any EasyController subclass
/// emit<OrderController>('order_placed', orderId);
///
/// // Receiver — OrderController
/// @override
/// List<EasyChannelBinding> get channelBindings => [
///   EasyChannelBinding<int>('order_placed', _onOrderPlaced),
/// ];
/// ```
///
/// ## Multi-scope injection
///
/// Use [EasyMultiScope] to nest several scopes without deeply indented code:
///
/// ```dart
/// EasyMultiScope(
///   entries: [
///     EasyScopeProvide(create: () => AuthController()),
///     EasyScopeProvide(create: () => CartController()),
///   ],
///   child: const MyApp(),
/// );
/// ```

// -----------------------------------------------------------------------------
// Part 1: Local Refresh Notifier
// -----------------------------------------------------------------------------

/// Synchronous, fine-grained UI refresh notifier.
///
/// Replaces `StreamController.broadcast()` with a `Map`-based callback
/// registry, eliminating async scheduling overhead:
///
/// | | Old (Stream) | New (_RefreshNotifier) |
/// |---|---|---|
/// | Dispatch | async microtask | synchronous call |
/// | Routing | linear scan of all subscribers | O(1) HashMap lookup by id |
///
/// A `null` key represents an "observe-all" consumer — one that has no
/// specific [EasyConsumer.id] and rebuilds on every [EasyController.refresh].
///
/// **Allocation strategy** — modelled after Flutter's `ChangeNotifier`:
/// Instead of copying the list before every iteration (`List.of()`), we track
/// the notification call depth and null-mark any callbacks removed during an
/// active iteration. Compaction runs once after the outermost `notify` returns,
/// so the common path (no structural changes during notification) is
/// allocation-free.
class _RefreshNotifier {
  // Nullable so removed-during-iteration slots can be null-marked.
  final Map<String?, List<VoidCallback?>> _listeners = {};

  /// > 0 while a [notify] call is on the stack (supports reentrant refresh).
  int _notifyingDepth = 0;

  /// Whether any slot was null-marked during the current notification round.
  bool _hasPendingRemovals = false;

  bool _disposed = false;

  void subscribe(String? id, VoidCallback callback) {
    assert(!_disposed, '_RefreshNotifier.subscribe called after dispose.');
    (_listeners[id] ??= []).add(callback);
  }

  void unsubscribe(String? id, VoidCallback callback) {
    final list = _listeners[id];
    if (list == null) return;

    if (_notifyingDepth > 0) {
      // Null-mark instead of remove to avoid ConcurrentModificationError.
      final i = list.indexOf(callback);
      if (i >= 0) {
        list[i] = null;
        _hasPendingRemovals = true;
      }
    } else {
      list.remove(callback);
      if (list.isEmpty) _listeners.remove(id);
    }
  }

  /// Notifies listeners.
  ///
  /// - [ids] is `null`: all listeners are notified (full refresh).
  /// - [ids] is non-null: only listeners whose key appears in [ids] are
  ///   notified (targeted refresh).
  void notify(List<String>? ids) {
    if (_disposed) return;
    _notifyingDepth++;

    try {
      if (ids == null) {
        for (final list in _listeners.values) {
          _notifyList(list);
        }
      } else {
        for (final id in ids) {
          final list = _listeners[id];
          if (list != null) _notifyList(list);
        }
      }
    } finally {
      _notifyingDepth--;
      // Compact only after the outermost notify returns (handles reentrant refresh).
      if (_notifyingDepth == 0 && _hasPendingRemovals) {
        _compact();
      }
    }
  }

  void _notifyList(List<VoidCallback?> list) {
    // Capture length before iteration: callbacks added during this round
    // (via subscribe inside a handler) are intentionally excluded.
    final len = list.length;
    for (var i = 0; i < len; i++) {
      list[i]?.call(); // null = removed during iteration, skip silently
    }
  }

  void _compact() {
    _hasPendingRemovals = false;
    _listeners.removeWhere((key, list) {
      list.removeWhere((cb) => cb == null);
      return list.isEmpty;
    });
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

// -----------------------------------------------------------------------------
// Part 2: Channel Bindings
// -----------------------------------------------------------------------------

/// Declares a subscription to a named channel within an [EasyController].
///
/// [T] is the type of the message payload. The [channel] string is the name
/// of the channel *within the target controller's namespace* — it does not
/// need to be globally unique.
///
/// Register bindings by overriding [EasyController.channelBindings]:
///
/// ```dart
/// @override
/// List<EasyChannelBinding> get channelBindings => [
///   EasyChannelBinding<OrderPlacedData>('order_placed', _onOrderPlaced),
/// ];
///
/// void _onOrderPlaced(OrderPlacedData data) {
///   // handle the message
///   refresh();
/// }
/// ```
///
/// **Always specify the type parameter explicitly.** Omitting `<T>` causes
/// type erasure — the handler will accept any payload — and triggers an
/// assertion failure in debug mode.
class EasyChannelBinding<T> {
  /// The channel name within the target controller's namespace.
  final String channel;

  /// The callback invoked when a message is received on [channel].
  final void Function(T data) handler;

  /// Creates a channel binding.
  ///
  /// Throws an [AssertionError] in debug mode if the type parameter [T] is
  /// omitted (i.e., inferred as `dynamic`).
  EasyChannelBinding(this.channel, this.handler) {
    assert(
      T != dynamic,
      '[Easy State] Type erasure detected in EasyChannelBinding.\n'
      'Specify the payload type explicitly.\n'
      'Correct: EasyChannelBinding<MyData>(channel, handler).',
    );
  }

  void _execute(dynamic data) {
    if (data is T) handler(data);
  }
}

/// Pairs a channel name with its raw handler for precise unregistration.
///
/// Used internally by [EasyController] to avoid Dart 3 record syntax,
/// keeping the minimum SDK requirement at Dart 2.17.
class _ChannelEntry {
  final String channel;
  final void Function(dynamic) handler;

  const _ChannelEntry(this.channel, this.handler);
}

// -----------------------------------------------------------------------------
// Part 3: Global Channel Bus
// -----------------------------------------------------------------------------

/// The interface for the global channel bus.
///
/// Implement this interface to provide a test double for [EasyChannel]:
///
/// ```dart
/// class MockChannelBus implements EasyChannelBus {
///   // ...
/// }
///
/// setUp(() => EasyChannel.override(MockChannelBus()));
/// tearDown(() => EasyChannel.reset());
/// ```
abstract class EasyChannelBus {
  /// Registers [handler] to receive messages on [channel] scoped to [controllerType].
  void listen(Type controllerType, String channel, void Function(dynamic) handler);

  /// Removes a previously registered [handler].
  void cancel(Type controllerType, String channel, void Function(dynamic) handler);

  /// Dispatches [data] to all handlers registered for [channel] under [targetType].
  void emit(Type targetType, String channel, dynamic data);

  /// Releases all resources held by this bus.
  void dispose();
}

/// Default [EasyChannelBus] implementation.
///
/// Uses a two-level `HashMap` (`controllerType → channelName → handlers`) for
/// O(1) routing. Controllers that share a channel name but target different
/// controller types are fully isolated.
class _ChannelBus implements EasyChannelBus {
  /// `controllerType → channelName → List<handler>`
  final Map<Type, Map<String, List<void Function(dynamic)>>> _registry = {};

  @override
  void listen(Type controllerType, String channel, void Function(dynamic) handler) {
    ((_registry[controllerType] ??= {})[channel] ??= []).add(handler);
  }

  @override
  void cancel(Type controllerType, String channel, void Function(dynamic) handler) {
    final channelMap = _registry[controllerType];
    if (channelMap != null) {
      final list = channelMap[channel];
      if (list != null) {
        list.remove(handler);
        if (list.isEmpty) {
          channelMap.remove(channel);
          if (channelMap.isEmpty) _registry.remove(controllerType);
        }
      }
    }
  }

  @override
  void emit(Type targetType, String channel, dynamic data) {
    final handlers = _registry[targetType]?[channel];
    if (handlers == null || handlers.isEmpty) return;
    // Snapshot the length before iteration. Handlers added mid-dispatch are
    // excluded from this round; handlers removed mid-dispatch are still called
    // (consistent with fire-and-forget channel semantics), but their
    // post-removal side-effects are isolated within the handler itself.
    final len = handlers.length;
    for (var i = 0; i < len; i++) {
      try {
        handlers[i](data);
      } catch (e, stack) {
        debugPrint('[EasyChannel] Unhandled error in "$channel" → $targetType: $e\n$stack');
      }
    }
  }

  @override
  void dispose() => _registry.clear();
}

/// Global registry for the channel bus.
///
/// In production code, you never call this class directly — use
/// [EasyController.emit] and [EasyController.channelBindings] instead.
///
/// In tests, replace the underlying bus with a mock:
///
/// ```dart
/// setUp(() => EasyChannel.override(MockChannelBus()));
/// tearDown(() => EasyChannel.reset());
/// ```
class EasyChannel {
  static EasyChannelBus _instance = _ChannelBus();

  /// The active [EasyChannelBus] instance.
  static EasyChannelBus get instance => _instance;

  /// Replaces the active bus with [bus].
  ///
  /// Intended for testing only. Call [reset] in `tearDown` to restore the
  /// default implementation.
  static void override(EasyChannelBus bus) => _instance = bus;

  /// Disposes the current bus and reinstalls the default implementation.
  static void reset() {
    _instance.dispose();
    _instance = _ChannelBus();
  }
}

// -----------------------------------------------------------------------------
// Part 4: Core Controller
// -----------------------------------------------------------------------------

/// Base class for all Easy State controllers.
///
/// A controller encapsulates business logic for a feature and drives UI
/// updates by calling [refresh]. It is provided to the widget tree through
/// [EasyScope] and consumed by [EasyConsumer].
///
/// ## Lifecycle
///
/// 1. [EasyScope] creates the controller and calls [initialize].
/// 2. The controller is active while the scope remains mounted.
/// 3. [EasyScope] calls [dispose] when it is removed from the tree.
///
/// Always call `super.initialize()` and `super.dispose()` when overriding.
///
/// ## Local refresh
///
/// Call [refresh] to rebuild the [EasyConsumer] widgets subscribed to this
/// controller. Pass [refresh] an `ids` list to target only specific consumers:
///
/// ```dart
/// void updateHeader() {
///   _title = 'New Title';
///   refresh(ids: ['header']); // only rebuilds EasyConsumer(id: 'header', ...)
/// }
/// ```
///
/// ## Cross-controller messaging
///
/// Override [channelBindings] to subscribe to messages from other controllers,
/// and call [emit] to send messages:
///
/// ```dart
/// class CartController extends EasyController {
///   @override
///   List<EasyChannelBinding> get channelBindings => [
///     EasyChannelBinding<int>('item_added', _onItemAdded),
///   ];
///
///   void _onItemAdded(int productId) { /* ... */ }
/// }
///
/// class ProductController extends EasyController {
///   void addToCart(int productId) {
///     emit<CartController>('item_added', productId);
///   }
/// }
/// ```
abstract class EasyController {
  bool _isDisposed = false;
  bool _isInitialized = false;

  /// Whether [dispose] has been called on this controller.
  bool get isDisposed => _isDisposed;

  /// Whether [initialize] has been called on this controller.
  bool get isInitialized => _isInitialized;

  final _RefreshNotifier _notifier = _RefreshNotifier();

  // Exposed to EasyConsumer for direct subscription — not part of the public API.
  _RefreshNotifier get _refreshNotifier => _notifier;

  Timer? _debounceTimer;

  // ---------------------------------------------------------------------------
  // Local UI refresh
  // ---------------------------------------------------------------------------

  /// Triggers a rebuild of the [EasyConsumer] widgets subscribed to this
  /// controller.
  ///
  /// - `refresh()` — notifies all consumers.
  /// - `refresh(ids: ['header'])` — notifies only consumers whose
  ///   [EasyConsumer.id] appears in [ids].
  /// - `refresh(ids: [...], debounce: Duration(milliseconds: 16))` — coalesces
  ///   rapid calls into a single notification after [debounce] elapses.
  ///   Useful for animation frames or high-frequency input events.
  ///
  /// Has no effect if [isDisposed] is `true`.
  @protected
  void refresh({List<String>? ids, Duration? debounce}) {
    if (_isDisposed) return;

    if (debounce != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        if (!_isDisposed) _notifier.notify(ids);
      });
    } else {
      _notifier.notify(ids);
    }
  }

  // ---------------------------------------------------------------------------
  // Cross-controller messaging
  // ---------------------------------------------------------------------------

  /// Sends [data] to all instances of controller type [C] that have registered
  /// a [EasyChannelBinding] for [channel].
  ///
  /// [C] **must** be specified explicitly. Omitting the type parameter causes
  /// an assertion failure in debug mode.
  ///
  /// ```dart
  /// emit<CartController>('item_added', productId);
  /// ```
  ///
  /// This method is `@protected` — only callable from within an
  /// [EasyController] subclass, enforcing the constraint that channels are
  /// strictly for controller-to-controller communication.
  @protected
  void emit<C extends EasyController>(String channel, dynamic data) {
    assert(
      C != EasyController,
      '[Easy State] Type erasure detected in emit().\n'
      'Specify the target controller type explicitly.\n'
      'Correct: emit<CartController>(channel, data).',
    );
    EasyChannel.instance.emit(C, channel, data);
  }

  /// Declares the channels this controller listens to.
  ///
  /// Override this getter to subscribe to messages from other controllers.
  /// The framework registers all bindings during [initialize] and unregisters
  /// them during [dispose] — no manual management is needed.
  ///
  /// ```dart
  /// @override
  /// List<EasyChannelBinding> get channelBindings => [
  ///   EasyChannelBinding<int>('item_added', _onItemAdded),
  /// ];
  /// ```
  @protected
  List<EasyChannelBinding> get channelBindings => [];

  // Stores channel + handler pairs for precise unregistration on dispose.
  // Uses a plain class instead of a Dart 3 record to stay compatible with Dart 2.17+.
  final List<_ChannelEntry> _registeredHandlers = [];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initializes the controller.
  ///
  /// Called automatically by [EasyScope]. Registers all [channelBindings]
  /// with the global [EasyChannel] bus.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Always call `super.initialize()` when overriding.
  @mustCallSuper
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    for (final binding in channelBindings) {
      EasyChannel.instance.listen(runtimeType, binding.channel, binding._execute);
      _registeredHandlers.add(_ChannelEntry(binding.channel, binding._execute));
    }
  }

  /// Releases all resources held by this controller.
  ///
  /// Called automatically by [EasyScope]. Cancels any pending debounce timer,
  /// unregisters all [channelBindings], and disposes the refresh notifier.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Always call `super.dispose()` when overriding.
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _debounceTimer?.cancel();

    for (final entry in _registeredHandlers) {
      EasyChannel.instance.cancel(runtimeType, entry.channel, entry.handler);
    }
    _registeredHandlers.clear();
    _notifier.dispose();
  }
}

// -----------------------------------------------------------------------------
// Part 5: Scope & Dependency Injection
// -----------------------------------------------------------------------------

class _EasyInheritedScope<T extends EasyController> extends InheritedWidget {
  final T controller;

  const _EasyInheritedScope({required this.controller, required super.child});

  @override
  bool updateShouldNotify(_EasyInheritedScope<T> oldWidget) =>
      oldWidget.controller != controller;
}

/// Signature for the builder callback used by [EasyScope].
typedef EasyScopeBuilder<T extends EasyController> = Widget Function(
  BuildContext context,
  T controller,
);

/// Provides an [EasyController] of type [T] to its widget subtree.
///
/// [EasyScope] uses Flutter's `InheritedWidget` mechanism, so any descendant
/// can look up the controller with [EasyScope.of] or [EasyScope.maybeOf].
///
/// ## Owned scope
///
/// Use the default constructor when the scope owns the controller's lifecycle.
/// [EasyScope] calls [EasyController.initialize] on mount and
/// [EasyController.dispose] on unmount.
///
/// ```dart
/// EasyScope<CounterController>(
///   create: () => CounterController(),
///   builder: (context, controller) => CounterView(),
/// );
/// ```
///
/// ## Shared scope
///
/// Use [EasyScope.value] to inject an already-initialized controller
/// (e.g., one shared across routes). The scope does **not** dispose it.
///
/// ```dart
/// EasyScope<AuthController>.value(
///   value: myAuthController, // must have initialize() already called
///   child: const ProfilePage(),
/// );
/// ```
///
/// ## Looking up the controller
///
/// ```dart
/// // Throws if not found — use inside a guaranteed subtree.
/// final controller = EasyScope.of<CounterController>(context);
///
/// // Returns null if not found — for optional dependencies.
/// final controller = EasyScope.maybeOf<CounterController>(context);
/// ```
class EasyScope<T extends EasyController> extends StatefulWidget {
  final T Function()? _create;
  final T? _value;

  /// An optional builder that receives the controller directly.
  ///
  /// Provide either [builder] or [child], not both.
  final EasyScopeBuilder<T>? builder;

  /// An optional child widget that does not need direct access to the controller.
  ///
  /// Provide either [builder] or [child], not both.
  final Widget? child;

  final bool _isShared;

  /// Creates an owned [EasyScope] that manages the controller's lifecycle.
  ///
  /// [create] is called once on mount. Provide exactly one of [builder] or [child].
  const EasyScope({
    required T Function() create,
    this.builder,
    this.child,
    super.key,
  })  : assert(
          (builder == null) != (child == null),
          '[Easy State] Provide either a builder or a child, but not both.',
        ),
        _create = create,
        _value = null,
        _isShared = false;

  /// Creates a shared [EasyScope] that wraps an externally managed controller.
  ///
  /// The provided [value] must already have had [EasyController.initialize]
  /// called. This scope does **not** call [EasyController.dispose].
  const EasyScope.value({
    required T value,
    this.builder,
    this.child,
    super.key,
  })  : assert(
          (builder == null) != (child == null),
          '[Easy State] Provide either a builder or a child, but not both.',
        ),
        _value = value,
        _create = null,
        _isShared = true;

  /// Returns the nearest [EasyController] of type [T], or `null` if none is found.
  static T? maybeOf<T extends EasyController>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_EasyInheritedScope<T>>()
        ?.controller;
  }

  /// Returns the nearest [EasyController] of type [T].
  ///
  /// Throws a [FlutterError] with actionable guidance if no [EasyScope] of
  /// type [T] is found in the current context.
  ///
  /// **Do not call this in async callbacks after `await`.** If the widget is
  /// unmounted before the callback fires, the `context` is no longer valid.
  /// Store the controller reference *before* the async gap instead:
  ///
  /// ```dart
  /// // Safe pattern
  /// Future<void> _load() async {
  ///   final ctrl = EasyScope.of<MyController>(context); // before await
  ///   final data = await fetchData();
  ///   ctrl.update(data); // safe — no context dependency after the gap
  /// }
  /// ```
  static T of<T extends EasyController>(BuildContext context) {
    final controller = maybeOf<T>(context);
    if (controller == null) {
      throw FlutterError.fromParts([
        ErrorSummary('[Easy State] EasyScope.of<$T> failed.'),
        ErrorDescription('No EasyScope<$T> was found in the current BuildContext.'),
        ErrorHint(
          'Make sure that:\n'
          '  1. The widget calling EasyScope.of<$T>() is a descendant of an '
          'EasyScope<$T>.\n'
          '  2. You have not crossed a Navigator barrier without injecting the '
          'controller on the new route.',
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
        '[Easy State] The controller passed to EasyScope<$T>.value has not been '
        'initialized. Call initialize() before injecting a shared instance.',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    assert(() {
      final ancestor =
          context.dependOnInheritedWidgetOfExactType<_EasyInheritedScope<T>>();
      if (ancestor != null && ancestor.controller != _controller) {
        throw FlutterError.fromParts([
          ErrorSummary('[Easy State] Nested EasyScope<$T> detected.'),
          ErrorDescription(
            'Two EasyScope<$T> instances are nested in the same widget tree, '
            'which makes EasyScope.of<$T> ambiguous.',
          ),
          ErrorHint(
            'Solutions:\n'
            '  1. Make the two scopes siblings rather than parent/child.\n'
            '  2. Create a distinct subclass of $T so each scope has a unique type.',
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
        '[Easy State] The replacement controller for EasyScope<$T>.value has not '
        'been initialized.',
      );
    }
  }

  @override
  void dispose() {
    if (!widget._isShared) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EasyInheritedScope<T>(
      controller: _controller,
      child: widget.child ??
          Builder(builder: (ctx) => widget.builder!(ctx, _controller)),
    );
  }
}

// -----------------------------------------------------------------------------
// Part 6: Reactive Consumer Widget
// -----------------------------------------------------------------------------

/// Signature for the builder callback used by [EasyConsumer].
typedef EasyConsumerBuilder<T extends EasyController> = Widget Function(
  BuildContext context,
  T controller,
);

/// A widget that rebuilds when its [EasyController] calls [EasyController.refresh].
///
/// [EasyConsumer] subscribes directly to the controller's synchronous notifier,
/// bypassing `Stream` and `ChangeNotifier` overhead. The `setState` call
/// happens in the same call stack as [EasyController.refresh].
///
/// Must be placed inside an [EasyScope] of the same type [T].
///
/// ## Full rebuild (no id)
///
/// ```dart
/// EasyConsumer<CounterController>(
///   builder: (context, controller) => Text('${controller.count}'),
/// );
/// ```
///
/// ## Targeted rebuild (with id)
///
/// Pass an [id] to rebuild only when `refresh(ids: ['footer'])` is called:
///
/// ```dart
/// EasyConsumer<CounterController>(
///   id: 'footer',
///   builder: (context, controller) => FooterWidget(controller),
/// );
/// ```
class EasyConsumer<T extends EasyController> extends StatefulWidget {
  /// When set, this consumer only rebuilds when [EasyController.refresh] is
  /// called with an `ids` list that contains this value.
  ///
  /// When `null`, the consumer rebuilds on every `refresh()` call.
  final String? id;

  /// Called whenever this consumer rebuilds.
  final EasyConsumerBuilder<T> builder;

  /// Creates an [EasyConsumer].
  const EasyConsumer({required this.builder, this.id, super.key});

  @override
  State<EasyConsumer<T>> createState() => _EasyConsumerState<T>();
}

class _EasyConsumerState<T extends EasyController>
    extends State<EasyConsumer<T>> {
  T? _controller;
  VoidCallback? _callback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resubscribe();
  }

  @override
  void didUpdateWidget(covariant EasyConsumer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.id != oldWidget.id) {
      _resubscribe(forceResubscribe: true);
    }
  }

  void _resubscribe({bool forceResubscribe = false}) {
    final newController = EasyScope.maybeOf<T>(context);

    if (!forceResubscribe && _controller == newController) return;

    _unsubscribe();
    _controller = newController;

    if (_controller != null && !_controller!.isDisposed) {
      _callback = _onRefresh;
      _controller!._refreshNotifier.subscribe(widget.id, _callback!);
    }
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  void _unsubscribe() {
    if (_controller != null && _callback != null) {
      _controller!._refreshNotifier.unsubscribe(widget.id, _callback!);
      _callback = null;
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      throw FlutterError.fromParts([
        ErrorSummary('[Easy State] EasyConsumer<$T> could not find its controller.'),
        ErrorDescription(
          'EasyConsumer<$T> must be placed inside an EasyScope<$T>.',
        ),
        ErrorHint(
          'Wrap the relevant part of your widget tree with '
          'EasyScope<$T>(create: () => $T(), ...).',
        ),
      ]);
    }
    return widget.builder(context, _controller!);
  }
}

// -----------------------------------------------------------------------------
// Part 7: Multi-Scope Injection
// -----------------------------------------------------------------------------

/// An entry in an [EasyMultiScope].
///
/// Implement this interface to create custom scope entries, or use the
/// built-in [EasyScopeProvide].
abstract class EasyScopeEntry {
  /// Wraps [child] with the scope provided by this entry.
  Widget build(Widget child);
}

/// An [EasyScopeEntry] that provides an [EasyController] of type [T].
///
/// Use the default constructor to let [EasyMultiScope] own the controller
/// lifecycle, or use [EasyScopeProvide.value] for a shared instance.
///
/// ```dart
/// EasyMultiScope(
///   entries: [
///     EasyScopeProvide(create: () => AuthController()),
///     EasyScopeProvide.value(value: sharedCartController),
///   ],
///   child: const MyApp(),
/// );
/// ```
class EasyScopeProvide<T extends EasyController> extends EasyScopeEntry {
  /// The factory used when the scope owns the controller.
  final T Function()? create;

  /// The pre-existing controller used when the scope is shared.
  final T? value;

  /// Whether this entry uses a shared (externally managed) controller.
  final bool isShared;

  /// Creates an entry that owns the controller's lifecycle.
  EasyScopeProvide({required this.create})
      : value = null,
        isShared = false;

  /// Creates an entry that wraps an already-initialized shared controller.
  EasyScopeProvide.value({required this.value})
      : create = null,
        isShared = true;

  @override
  Widget build(Widget child) {
    return isShared
        ? EasyScope<T>.value(value: value!, child: child)
        : EasyScope<T>(create: create!, child: child);
  }
}

/// Nests multiple [EasyScope] instances without deeply indented code.
///
/// [entries] are applied from outermost to innermost: `entries[0]` is the
/// highest ancestor, so controllers declared earlier are accessible to all
/// controllers declared later.
///
/// ```dart
/// EasyMultiScope(
///   entries: [
///     EasyScopeProvide(create: () => AuthController()),   // outermost
///     EasyScopeProvide(create: () => CartController()),   // can see AuthController
///   ],
///   child: const HomeScreen(),
/// );
/// ```
class EasyMultiScope extends StatelessWidget {
  /// The scope entries to nest, ordered from outermost to innermost.
  final List<EasyScopeEntry> entries;

  /// The widget below all injected scopes.
  final Widget child;

  /// Creates an [EasyMultiScope].
  const EasyMultiScope({
    required this.entries,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    Widget current = child;
    for (final entry in entries.reversed) {
      current = entry.build(current);
    }
    return current;
  }
}
