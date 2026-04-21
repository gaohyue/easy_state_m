## 1.2.1

* Fix compatibility: replace Dart 3 record type `(String, void Function(dynamic))`
  with private class `_ChannelEntry` to support Dart 2.17+.
* Update SDK constraint from `^3.11.0` to `>=2.17.0 <4.0.0` (Flutter >= 3.0.0).
* Fix example pubspec: rename dependency key `easy_state` → `easy_state_m` to match
  the package name, and update all import paths accordingly.

## 1.2.0

### Breaking Changes

* Removed `EasyEvent`, `EasyEventBinding`, `EasyEventBus`, and `EasyBusRegistry`.
  The event-driven cross-controller API has been replaced by a typed channel system (see below).
* Renamed `MultiEasyScope` → `EasyMultiScope` for naming consistency with the rest of the API.
* `EasyScopeBinding` replaced by `EasyScopeProvide` / `EasyScopeProvide.value`.

### New Features

* **Typed channel bus** — zero-coupling cross-controller messaging.
  * `EasyChannelBinding<T>` — declarative, type-safe channel subscription.
    Declare subscriptions by overriding `EasyController.channelBindings`.
  * `EasyController.emit<C>(channel, data)` — sends a message to all instances
    of controller type `C` that have registered a binding for `channel`.
    Annotated `@protected`; only callable from within `EasyController` subclasses.
  * `EasyChannelBus` — public abstract interface for the channel bus,
    enabling clean test doubles via `EasyChannel.override(mock)`.
  * `EasyChannel` — global registry with `override()` and `reset()` for testing.
  * Channel names are automatically namespaced by the target controller's `runtimeType`,
    so the same channel name in different controllers never collides.

* **`_RefreshNotifier` — allocation-free hot path.**
  Replaced `List.of()` defensive copies with an iteration-depth counter and null-mark
  strategy (modelled after Flutter's `ChangeNotifier`). The common path — no structural
  changes during notification — is now fully allocation-free. Compaction runs once after
  the outermost `notify` returns, and reentrant `refresh()` calls are handled correctly
  via a depth counter.

* **`_ChannelBus.emit` — index-based iteration.**
  Replaced `List.of(handlers)` with a length-snapshot loop, eliminating one temporary
  list allocation per dispatch.

### Improvements

* `EasyChannelBinding` constructor asserts that the type parameter `T` is not `dynamic`,
  catching type-erasure bugs at construction time in debug mode.
* `EasyController.emit<C>` asserts that `C` is not the base `EasyController` type,
  preventing silent no-op dispatches caused by a missing generic argument.
* `EasyScope.of<T>` documentation updated with an async-safety pattern: store the
  controller reference before any `await` to avoid accessing an invalidated `BuildContext`.
* Full English API documentation on all public classes and members (pub.dev standard).
* Updated `README.md` with architecture diagram, data-flow table, performance notes,
  and complete bilingual (English / 中文) usage guide.

## 1.0.2

* Add Support Files.

## 1.1.0
* Add MultiEasyScope
* Update README.md

## 1.0.0

* Initial release of Easy State.
* Added `EasyController` and `EasyScope` for O(1) dependency injection.
* Added `EasyEvent` and `_EasyEventBus` for multi-way data synchronization.
* Added `EasyConsumer` for granular local UI rebuilds.
* Implemented strict architectural guardrails and assertions.


