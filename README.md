# easy_state_m

A lightweight, performance-optimized state management framework for Flutter.

**[English](#english)** | **[中文](#中文)**

---

# English

## Overview

`easy_state_m` is built around three ideas:

1. **Localized state** — each feature owns its state in an `EasyController`, scoped to a widget subtree via `EasyScope`. No global singletons, no accidental cross-feature pollution.
2. **Surgical UI refresh** — `EasyConsumer` widgets subscribe directly to a synchronous notifier. Pass an `id` to rebuild only the exact widget that changed, leaving everything else untouched.
3. **Typed cross-controller messaging** — sibling scopes communicate through named channels. The sender specifies the target controller type as a generic parameter; the channel bus routes the message with O(1) HashMap lookups. No shared state, no tight coupling.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Widget Tree                                │
│                                                                      │
│  EasyMultiScope                                                      │
│  ├─ EasyScope<AuthController>   (owned — manages lifecycle)          │
│  └─ EasyScope<CartController>   (shared — external lifecycle)        │
│         │                              │                             │
│         │  InheritedWidget lookup      │  refresh(ids: ['badge'])    │
│         ▼                              │  (synchronous, zero alloc)  │
│  EasyConsumer<CartController>          │                             │
│  id: 'badge'  ◄────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘
                         ▲
      emit<CartController>('item_added', product)
      (@protected — only callable from EasyController subclasses)
                         │
         ┌───────────────┴────────────────┐
         │        ProductController        │
         │        (EasyController)         │
         └───────────────┬────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │          EasyChannel          │  Global channel bus
         │  (controllerType →            │  O(1) two-level HashMap
         │   channelName → handlers)     │  Type-namespaced routing
         └───────────────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │        CartController         │
         │  channelBindings:             │
         │  EasyChannelBinding<Product>  │
         │  ('item_added', _onItem)      │
         └───────────────────────────────┘
```

### Data flow

| Step | What happens |
|---|---|
| `EasyScope` mounts | Creates controller, calls `initialize()`, registers channel bindings |
| `EasyConsumer` mounts | Subscribes `setState` callback to `_RefreshNotifier` (synchronous, no `Stream`) |
| Controller calls `refresh()` | `_RefreshNotifier` dispatches callbacks in-place — `setState` fires in the same call stack |
| Controller calls `emit<C>(channel, data)` | `EasyChannel` routes to all `C` instances that declared a binding for that channel |
| `EasyScope` unmounts | Calls `dispose()`, unregisters channel bindings, cancels debounce timers |

---

## Performance Notes

### Local refresh — zero allocation on the hot path

`_RefreshNotifier` uses an **iteration-depth + null-mark** strategy (modelled after Flutter's own `ChangeNotifier`):

- No `List.of()` copy is made on every `notify()` call.
- If a callback is removed *during* notification, the slot is null-marked and skipped inline.
- Compaction (removing null slots) runs once after the outermost `notify` returns.
- The common case — no structural changes during notification — is fully allocation-free.

### Cross-controller messaging — O(1) routing

`_ChannelBus` uses a two-level `HashMap`:

```
controllerType  →  channelName  →  List<handler>
```

Dispatching a message requires exactly two HashMap lookups regardless of how many controllers or channels exist in the app. Unrelated controllers are never woken up.

---

## Installation

```yaml
dependencies:
  easy_state_m: ^1.2.1
```

---

## Quick Start

### 1. Define a controller

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh();                        // rebuilds all consumers
  }

  void incrementHeader() {
    count++;
    refresh(ids: ['header']);         // rebuilds only EasyConsumer(id: 'header')
  }

  void incrementDebounced() {
    count++;
    refresh(debounce: Duration(milliseconds: 16)); // coalesces rapid calls
  }
}
```

### 2. Provide it with EasyScope

```dart
EasyScope<CounterController>(
  create: () => CounterController(),   // owned — scope manages lifecycle
  builder: (context, controller) {
    return Scaffold(
      body: EasyConsumer<CounterController>(
        builder: (context, ctrl) => Text('${ctrl.count}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.increment,
        child: const Icon(Icons.add),
      ),
    );
  },
);
```

### 3. Look up the controller anywhere in the subtree

```dart
// Throws if not found — use when the scope is guaranteed to exist.
final ctrl = EasyScope.of<CounterController>(context);

// Returns null if not found — use for optional dependencies.
final ctrl = EasyScope.maybeOf<CounterController>(context);
```

> **Async safety** — store the controller reference *before* any `await`. After the async gap the widget may have unmounted and the `context` is no longer valid:
> ```dart
> Future<void> load() async {
>   final ctrl = EasyScope.of<MyController>(context); // before await ✓
>   final data = await fetchData();
>   ctrl.update(data);                                // no context needed ✓
> }
> ```

---

## Targeted Rebuild

Give each `EasyConsumer` a unique `id` and call `refresh(ids: [...])` to rebuild only the matching widgets. All other consumers are untouched, no matter how many there are.

```dart
// Controller
void updateRow(int index) {
  items[index].value++;
  refresh(ids: ['row_$index']);   // only the tapped row rebuilds
}

// Widget
ListView.builder(
  itemBuilder: (context, index) => EasyConsumer<ListController>(
    id: 'row_$index',
    builder: (context, ctrl) => ListTile(title: Text('${ctrl.items[index].value}')),
  ),
);
```

---

## Cross-Controller Messaging

Controllers in sibling scopes communicate through **named channels**. Channels are automatically namespaced by the target controller's `runtimeType`, so the same channel name in different controllers never collides.

```dart
// Receiver — CartController
class CartController extends EasyController {
  int itemCount = 0;

  @override
  List<EasyChannelBinding> get channelBindings => [
    EasyChannelBinding<String>('item_added', _onItemAdded),
  ];

  void _onItemAdded(String productName) {
    itemCount++;
    refresh();
  }
}

// Sender — ProductController (no import of CartController's internals)
class ProductController extends EasyController {
  void addToCart(String productName) {
    emit<CartController>('item_added', productName);
    //   ^^^^^^^^^^^^^^^ target type  ^^^^^^^^^^^^^ channel name
  }
}
```

**Rules:**
- Always specify the type parameter on `EasyChannelBinding<T>` and `emit<C>`. Omitting either triggers an `AssertionError` in debug mode.
- `emit` is `@protected` — only callable from within an `EasyController` subclass. This enforces the constraint that channels are strictly for controller-to-controller communication.

---

## Multi-Scope Injection

Use `EasyMultiScope` to nest multiple scopes without deeply indented code. Entries are ordered outermost-first: `entries[0]` is the highest ancestor and is accessible to all controllers declared after it.

```dart
// main.dart
final authController = AuthController()..initialize();

EasyMultiScope(
  entries: [
    EasyScopeProvide.value(value: authController),   // shared — lifecycle managed externally
    EasyScopeProvide(create: () => ThemeController()), // owned — disposed with the scope
  ],
  child: const MyApp(),
);
```

---

## Shared Scope

Use `EasyScope.value` to inject an already-initialized controller across Navigator barriers or into children that should not own the lifecycle.

```dart
// Parent creates and owns the controller.
final controller = MyController()..initialize();

// Pass it into a new route.
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => EasyScope<MyController>.value(
    value: controller,
    child: const ChildPage(),
  ),
));
```

`EasyScope.value` **does not** call `dispose()` when unmounted.

---

## Testing

Replace the channel bus with a mock in `setUp` and restore it in `tearDown`:

```dart
class MockChannelBus implements EasyChannelBus {
  final List<String> log = [];

  @override void listen(Type ct, String ch, void Function(dynamic) h) {}
  @override void cancel(Type ct, String ch, void Function(dynamic) h) {}
  @override void emit(Type t, String ch, dynamic d) => log.add('$t/$ch/$d');
  @override void dispose() {}
}

setUp(() => EasyChannel.override(MockChannelBus()));
tearDown(() => EasyChannel.reset());
```

---

## API Reference

| Class | Role |
|---|---|
| `EasyController` | Base class for business logic. Override `channelBindings`, call `refresh()` and `emit<C>()`. |
| `EasyScope<T>` | Provides `T` to a widget subtree via `InheritedWidget`. Owns or shares the lifecycle. |
| `EasyConsumer<T>` | Rebuilds when the controller calls `refresh()`. Optionally scoped by `id`. |
| `EasyMultiScope` | Nests multiple `EasyScope` instances without deep indentation. |
| `EasyScopeProvide<T>` | An `EasyMultiScope` entry. Use `.value(value: ...)` for shared instances. |
| `EasyChannelBinding<T>` | Declares a channel subscription with a typed payload. |
| `EasyChannelBus` | Abstract interface for the channel bus. Implement to provide test doubles. |
| `EasyChannel` | Global registry. Use `override` / `reset` in tests. |

---

## Common Pitfalls

| Mistake | What happens | Fix |
|---|---|---|
| Nesting two `EasyScope<T>` of the same type | `FlutterError` thrown in debug mode | Make scopes siblings, or subclass `T` |
| Omitting `<T>` on `EasyChannelBinding` | `AssertionError` in debug mode | `EasyChannelBinding<MyType>(...)` |
| Omitting `<C>` on `emit` | `AssertionError` in debug mode | `emit<TargetController>(...)` |
| Injecting an uninitialized shared controller | `AssertionError` in debug mode | Call `initialize()` before passing to `EasyScope.value` |
| Calling `EasyScope.of(context)` after `await` | Potential `context` invalidation | Store the controller before the async gap |

---

## License

MIT

---
---

# 中文

## 概述

`easy_state_m` 围绕三个核心思想构建：

1. **状态局部化** — 每个功能模块的状态收敛到一个 `EasyController`，通过 `EasyScope` 挂载到 Widget 子树。没有全局单例，没有跨模块意外污染。
2. **精准 UI 刷新** — `EasyConsumer` 直接订阅同步通知器。传入 `id` 可只重建那一个 Widget，其余所有组件保持静止。
3. **类型化跨控制器通信** — 平级 Scope 之间通过命名频道通信。发送方用泛型参数指定目标 Controller 类型，Channel Bus 以 O(1) 的 HashMap 查找完成路由。无共享状态，无紧耦合。

---

## 架构图

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Widget Tree                                │
│                                                                      │
│  EasyMultiScope                                                      │
│  ├─ EasyScope<AuthController>   (owned — 管理生命周期)                │
│  └─ EasyScope<CartController>   (shared — 外部管理生命周期)            │
│         │                              │                             │
│         │  InheritedWidget 查找         │  refresh(ids: ['badge'])   │
│         ▼                              │  (同步派发，零分配)           │
│  EasyConsumer<CartController>          │                             │
│  id: 'badge'  ◄────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘
                         ▲
      emit<CartController>('item_added', product)
      (@protected — 只能在 EasyController 子类内部调用)
                         │
         ┌───────────────┴────────────────┐
         │        ProductController        │
         │        (EasyController)         │
         └───────────────┬────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │          EasyChannel          │  全局频道总线
         │  (controllerType →            │  O(1) 双层 HashMap
         │   channelName → handlers)     │  类型自动命名空间
         └───────────────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │        CartController         │
         │  channelBindings:             │
         │  EasyChannelBinding<Product>  │
         │  ('item_added', _onItem)      │
         └───────────────────────────────┘
```

### 数据流

| 步骤 | 发生了什么 |
|---|---|
| `EasyScope` 挂载 | 创建 Controller，调用 `initialize()`，注册频道绑定 |
| `EasyConsumer` 挂载 | 将 `setState` 回调订阅到 `_RefreshNotifier`（同步，无 Stream） |
| Controller 调用 `refresh()` | `_RefreshNotifier` 就地派发回调，`setState` 在同一调用栈内触发 |
| Controller 调用 `emit<C>(channel, data)` | `EasyChannel` 路由到所有声明了该频道绑定的 `C` 实例 |
| `EasyScope` 卸载 | 调用 `dispose()`，注销频道绑定，取消去抖 Timer |

---

## 性能说明

### 本地刷新 — 热路径零分配

`_RefreshNotifier` 采用 **迭代深度计数 + null 标记**策略（参考 Flutter 内置 `ChangeNotifier`）：

- `notify()` 不再每次调用 `List.of()` 创建副本。
- 通知过程中若有回调被移除，对应槽位标为 null，迭代时跳过。
- 紧凑化（清理 null 槽）在最外层 `notify` 返回后统一执行。
- 正常路径（通知期间无结构变更）完全零分配。

### 跨控制器通信 — O(1) 路由

`_ChannelBus` 采用双层 HashMap：

```
controllerType  →  channelName  →  List<handler>
```

派发一条消息只需恰好两次 HashMap 查找，与应用中 Controller 的数量、频道数量无关。无关 Controller 完全不被唤醒。

---

## 安装

```yaml
dependencies:
  easy_state_m: ^1.2.1
```

---

## 快速上手

### 1. 定义 Controller

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh();                         // 刷新所有消费者
  }

  void incrementHeader() {
    count++;
    refresh(ids: ['header']);          // 只刷新 EasyConsumer(id: 'header')
  }

  void incrementDebounced() {
    count++;
    refresh(debounce: Duration(milliseconds: 16)); // 合并高频调用
  }
}
```

### 2. 用 EasyScope 提供 Controller

```dart
EasyScope<CounterController>(
  create: () => CounterController(),   // owned — Scope 管理生命周期
  builder: (context, controller) {
    return Scaffold(
      body: EasyConsumer<CounterController>(
        builder: (context, ctrl) => Text('计数: ${ctrl.count}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.increment,
        child: const Icon(Icons.add),
      ),
    );
  },
);
```

### 3. 在子树任意位置查找 Controller

```dart
// 找不到时抛出 FlutterError（适用于有保证的子树内）
final ctrl = EasyScope.of<CounterController>(context);

// 找不到时返回 null（适用于可选依赖）
final ctrl = EasyScope.maybeOf<CounterController>(context);
```

> **异步安全** — 在任何 `await` 之前存储 Controller 引用。异步间隙之后 Widget 可能已卸载，`context` 不再有效：
> ```dart
> Future<void> load() async {
>   final ctrl = EasyScope.of<MyController>(context); // await 之前 ✓
>   final data = await fetchData();
>   ctrl.update(data);                                // 不再依赖 context ✓
> }
> ```

---

## 精准局部刷新

给每个 `EasyConsumer` 设置唯一 `id`，配合 `refresh(ids: [...])` 只重建匹配的 Widget，无论页面上有多少个 Consumer，其余全部静止不动。

```dart
// Controller
void updateRow(int index) {
  items[index].value++;
  refresh(ids: ['row_$index']);   // 只有被点击的那一行重建
}

// Widget
ListView.builder(
  itemBuilder: (context, index) => EasyConsumer<ListController>(
    id: 'row_$index',
    builder: (context, ctrl) => ListTile(
      title: Text('${ctrl.items[index].value}'),
    ),
  ),
);
```

---

## 跨控制器通信（Channel）

平级 Scope 下的 Controller 通过**命名频道**通信。频道以目标 Controller 的 `runtimeType` 为命名空间自动隔离，不同 Controller 中的同名频道绝不互相干扰。

```dart
// 接收方 — CartController
class CartController extends EasyController {
  int itemCount = 0;

  @override
  List<EasyChannelBinding> get channelBindings => [
    EasyChannelBinding<String>('item_added', _onItemAdded),
  ];

  void _onItemAdded(String productName) {
    itemCount++;
    refresh();
  }
}

// 发送方 — ProductController（无需 import CartController 内部实现）
class ProductController extends EasyController {
  void addToCart(String productName) {
    emit<CartController>('item_added', productName);
    //   ^^^^^^^^^^^^^^  目标类型     ^^^^^^^^^^^^^ 频道名
  }
}
```

**使用规则：**
- `EasyChannelBinding<T>` 和 `emit<C>` 都**必须**显式指定泛型。省略任一个都会在 Debug 模式下触发 `AssertionError`。
- `emit` 是 `@protected` 方法，只能在 `EasyController` 子类内部调用，框架层面强制约束"频道只用于 Controller 之间通信"。

---

## 多 Scope 注入

用 `EasyMultiScope` 嵌套多个 Scope，避免深层缩进。`entries` 按由外到内顺序排列：`entries[0]` 是最外层祖先，可被所有后续 Controller 访问。

```dart
// main.dart
final authController = AuthController()..initialize();

EasyMultiScope(
  entries: [
    EasyScopeProvide.value(value: authController),    // shared — 外部管理生命周期
    EasyScopeProvide(create: () => ThemeController()), // owned  — 随 Scope 销毁
  ],
  child: const MyApp(),
);
```

---

## 共享 Scope

跨路由共享同一个 Controller 实例时，用 `EasyScope.value` 注入，Scope 卸载时**不会**调用 `dispose()`。

```dart
// 外部创建并持有 Controller
final controller = MyController()..initialize();

// 注入到新路由
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => EasyScope<MyController>.value(
    value: controller,
    child: const ChildPage(),
  ),
));
```

---

## 测试

在 `setUp` 中替换 Channel Bus，在 `tearDown` 中还原：

```dart
class MockChannelBus implements EasyChannelBus {
  final List<String> log = [];

  @override void listen(Type ct, String ch, void Function(dynamic) h) {}
  @override void cancel(Type ct, String ch, void Function(dynamic) h) {}
  @override void emit(Type t, String ch, dynamic d) => log.add('$t/$ch/$d');
  @override void dispose() {}
}

setUp(() => EasyChannel.override(MockChannelBus()));
tearDown(() => EasyChannel.reset());
```

---

## API 一览

| 类 | 职责 |
|---|---|
| `EasyController` | 业务逻辑基类。覆写 `channelBindings`，调用 `refresh()` 和 `emit<C>()`。 |
| `EasyScope<T>` | 通过 `InheritedWidget` 向子树提供 `T`。支持 owned / shared 两种模式。 |
| `EasyConsumer<T>` | Controller 调用 `refresh()` 时重建。可通过 `id` 限定为精准刷新。 |
| `EasyMultiScope` | 无嵌套缩进地注入多个 `EasyScope`。 |
| `EasyScopeProvide<T>` | `EasyMultiScope` 的条目。`.value(value: ...)` 用于共享实例。 |
| `EasyChannelBinding<T>` | 声明一个带类型载荷的频道订阅。 |
| `EasyChannelBus` | 频道总线抽象接口，实现它以提供测试替身。 |
| `EasyChannel` | 全局注册表。测试中用 `override` / `reset` 替换实现。 |

---

## 常见错误

| 错误 | 后果 | 修正 |
|---|---|---|
| 嵌套两个同类型 `EasyScope<T>` | Debug 模式抛出 `FlutterError` | 改为兄弟节点，或将 `T` 子类化 |
| `EasyChannelBinding` 省略 `<T>` | Debug 模式抛出 `AssertionError` | 显式写 `EasyChannelBinding<MyType>(...)` |
| `emit` 省略 `<C>` | Debug 模式抛出 `AssertionError` | 显式写 `emit<TargetController>(...)` |
| 注入未初始化的共享 Controller | Debug 模式抛出 `AssertionError` | 传入前调用 `initialize()` |
| `await` 后调用 `EasyScope.of(context)` | context 可能已失效 | 在 `await` 之前存储 Controller 引用 |

---

## 开源协议

MIT
