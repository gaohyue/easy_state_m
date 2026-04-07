# Easy State Management Framework

A lightweight, high-performance, and easy-to-use Flutter state management framework
based on event-driven architecture, dependency injection, and reactive UI.

---

## Language
[English](#English) | [中文](#中文)

---
# English

## Overview

easy_state_m is a lightweight, high-performance state management framework for Flutter.
It provides strict UI-business decoupling, localized state, precise partial UI refresh,
and lifecycle-safe dependency injection.

## Architecture Diagram

```text
=======================================================================
               [ Communication Layer (Stateless) ]
=======================================================================
                               |
                               | 1. broadcast(EasyEvent)
                               v
                     +-------------------+
                     |  _EasyEventBus    | (Pure Message Broker)
                     +-------------------+
                               |
                               | 2. Precise Event Routing
                               v
=======================================================================
                [ State Management Layer (Memory) ]
=======================================================================
                     +-------------------+
                     | EasyController<T> | (State Container)
                     | - Local State     |
                     | - Event Bindings  |
                     +-------------------+
                       ^       |       ^
   3. initialize() /   |       |       |
      dispose()        |       |       |  4. refresh(ids: ['x'])
                       |       |       |     (Local Stream)
=======================|=======|=======|===============================
               [ Flutter Widget Tree (Context) ]
=======================|=======|=======|===============================
                       |       |       |
+----------------------+--+    |       |
| MultiEasyScope          |    |       |
|  └─ EasyScope<T> -------+----+       |
|      (InheritedWidget)  |            |
+-------------------------+            |
           |                           |
           | 5. EasyScope.of(context)  |
           v                           |
+-------------------------+            |
| EasyConsumer<T>         | <----------+
| (Precise UI Rebuilds)   |
+-------------------------+
```

## Core Concepts

### EasyScope
- State scope management based on `InheritedWidget` with O(1) lookup.
- Automatically manages controller lifecycle: `initialize()` and `dispose()`.
- Strict scope isolation eliminates global state pollution and memory leaks.

### EasyController
- Centralized state container and business logic handler.
- Fully decoupled from UI elements.
- Uses stream for partial UI refresh.
- Declarative event binding via `eventBindings`.

### EasyConsumer
- Reactive UI builder that listens to state changes.
- Supports ID-based precise rebuilding to avoid unnecessary renders.
- Pure view layer with zero business logic.

## Key Advantages

- **Localized state, no global pollution**
  - State is scoped to a particular widget subtree, avoiding conflicts and side effects.

- **Automatic lifecycle management**
  Controllers are created and disposed automatically with the widget tree.

- **Efficient & precise UI refresh**
  - Refresh only target widgets by ID, greatly improving performance.

- **Strict UI-business separation**
  - UI only renders data; all logic resides in the controller.

- **Loosely coupled event communication**
  - Components communicate via events without direct dependencies.

## Installation

```yaml
dependencies:
  easy_state_m: ^1.1.0
```

## Usage

### Single Page State Management

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh(ids: ['counter_text']);
  }
}

class CounterPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EasyScope<CounterController>(
      create: () => CounterController(),
      builder: (context, controller) => Scaffold(
        body: Center(
          child: EasyConsumer<CounterController>(
            id: 'counter_text',
            builder: (context, ctrl) => Text('Count: ${ctrl.count}'),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: controller.increment,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
```

### Global State & Multi Injection

```dart
class ThemeController extends EasyController {
  bool isDarkMode = false;

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    refresh();
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiEasyScope(
      bindings: [
        EasyScopeBinding<ThemeController>(create: () => ThemeController()),
      ],
      child: EasyConsumer<ThemeController>(
        builder: (context, themeCtrl) {
          return MaterialApp(
            title: 'Easy State Demo',
            theme: themeCtrl.isDarkMode ? ThemeData.dark() : ThemeData.light(),
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
```

### Cross-Page Communication

```dart
class UserLoginEvent extends EasyEvent {
  final String userName;
  UserLoginEvent(this.userName);

  @override
  Type get targetController => DashboardController;
}

class DashboardController extends EasyController {
  String currentUserName = "Not Logged In";

  @override
  List<EasyEventBinding> get eventBindings => [
        EasyEventBinding<UserLoginEvent>((event) {
          currentUserName = event.userName;
          refresh();
        }),
      ];
}

// Broadcast event
//EasyController.broadcast(UserLoginEvent("token"));
```

## Notes

- Do NOT nest multiple scopes of the same controller type.
- Always use explicit generic types for `EasyEventBinding<T>`.
- Manually call `initialize()` when using `EasyScope.value()`.

## License

MIT

---

---

# 中文

## 简介

easy_state_m 是一款轻量、高性能、易于使用的 Flutter 状态管理框架，
基于事件驱动 + 依赖注入 + 响应式 UI 构建，专注局部状态、精准刷新与强解耦架构。

## 架构图

```text
=======================================================================
               [ Communication Layer (Stateless) ]
=======================================================================
                               |
                               | 1. broadcast(EasyEvent)
                               v
                     +-------------------+
                     |  _EasyEventBus    | (Pure Message Broker)
                     +-------------------+
                               |
                               | 2. Precise Event Routing
                               v
=======================================================================
                [ State Management Layer (Memory) ]
=======================================================================
                     +-------------------+
                     | EasyController<T> | (State Container)
                     | - Local State     |
                     | - Event Bindings  |
                     +-------------------+
                       ^       |       ^
   3. initialize() /   |       |       |
      dispose()        |       |       |  4. refresh(ids: ['x'])
                       |       |       |     (Local Stream)
=======================|=======|=======|===============================
               [ Flutter Widget Tree (Context) ]
=======================|=======|=======|===============================
                       |       |       |
+----------------------+--+    |       |
| MultiEasyScope          |    |       |
|  └─ EasyScope<T> -------+----+       |
|      (InheritedWidget)  |            |
+-------------------------+            |
           |                           |
           | 5. EasyScope.of(context)  |
           v                           |
+-------------------------+            |
| EasyConsumer<T>         | <----------+
| (Precise UI Rebuilds)   |
+-------------------------+
```

## 核心概念

### EasyScope
- 基于 InheritedWidget 的状态作用域，提供 O(1) 快速查找。
- 自动管理控制器生命周期，执行 initialize / dispose。
- 严格作用域隔离，避免全局状态污染与内存泄漏。

### EasyController
- 局部状态与业务逻辑统一载体。
- 与 UI 层完全解耦。
- 基于 Stream 实现局部精准刷新。
- 通过 eventBindings 声明式监听事件。

### EasyConsumer
- 响应式 UI 消费组件。
- 支持按 ID 精准刷新，减少无用重建。
- 纯视图层，不包含任何业务逻辑。

## 核心优势

- **状态局部化，不污染全局**
  - 状态严格限定在当前作用域，无全局冲突、无意外副作用。

- **生命周期自动管理**
  - 控制器随组件树自动创建、销毁，内存更安全。

- **UI 高效精准刷新**
  - 按 ID 局部刷新，只重建需要更新的组件，性能大幅提升。

- **UI 与业务逻辑彻底解耦**
  - UI 只负责渲染，逻辑全部收敛于控制器。

- **事件驱动，组件零耦合通信**
  - 跨页面、跨组件通过事件通信，无需互相依赖。

## 安装

```yaml
dependencies:
  easy_state_m: ^1.1.0
```

## 使用示例

### 单页面状态管理

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh(ids: ['counter_text']);
  }
}

class CounterPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EasyScope<CounterController>(
      create: () => CounterController(),
      builder: (context, controller) => Scaffold(
        body: Center(
          child: EasyConsumer<CounterController>(
            id: 'counter_text',
            builder: (context, ctrl) => Text('计数: ${ctrl.count}'),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: controller.increment,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
```

### 全局状态与多控制器注入

```dart
class ThemeController extends EasyController {
  bool isDarkMode = false;

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    refresh();
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiEasyScope(
      bindings: [
        EasyScopeBinding<ThemeController>(create: () => ThemeController()),
      ],
      child: EasyConsumer<ThemeController>(
        builder: (context, themeCtrl) {
          return MaterialApp(
            title: 'Easy State Demo',
            theme: themeCtrl.isDarkMode ? ThemeData.dark() : ThemeData.light(),
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
```

### 跨页面通信

```dart
class UserLoginEvent extends EasyEvent {
  final String userName;
  UserLoginEvent(this.userName);

  @override
  Type get targetController => DashboardController;
}

class DashboardController extends EasyController {
  String currentUserName = "未登录";

  @override
  List<EasyEventBinding> get eventBindings => [
        EasyEventBinding<UserLoginEvent>((event) {
          currentUserName = event.userName;
          refresh();
        }),
      ];
}

// 发送事件
//EasyController.broadcast(UserLoginEvent("token"));
```

## 注意事项

- 禁止嵌套同类型 EasyScope。
- 事件绑定必须使用明确泛型，禁止使用基类或 dynamic。
- 使用 EasyScope.value() 时需手动调用 initialize()。

## 开源协议

MIT
```