# Easy State Management Framework

[English](#english) | [中文](#中文)

---

# 中文

## 🚀 简介

**Easy State Management Framework** 是一个轻量级、高性能、强类型安全的 Flutter 状态管理微框架。

它专注于：

* ⚡ O(1) 级别的状态访问
* 🧠 强类型约束（避免运行时错误）
* 🧩 高度解耦的事件驱动架构

适用于中大型项目，以及对架构质量有较高要求的场景。

---

## ✨ 特性

* **事件驱动（Event-Driven）**：基于全局 EventBus 实现模块解耦
* **精确刷新（Fine-grained Rebuild）**：支持按 ID 局部刷新 UI
* **零侵入（Non-intrusive）**：不污染业务代码
* **强类型安全（Strict Type Safety）**：避免类型擦除与运行时崩溃

---

## 📦 安装
```yaml
dependencies:
  easy_state: ^1.0.2
```

---

## 🧱 核心概念

### 1. EasyController

状态与业务逻辑中心：

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh();
  }
}
```

---

### 2. EasyScope（依赖注入）

```dart
EasyScope(
  create: () => CounterController(),
  builder: (context, controller) {
    return CounterPage();
  },
)
```

---

### 3. EasyConsumer（UI响应）

```dart
EasyConsumer<CounterController>(
  builder: (context, controller) {
    return Text('${controller.count}');
  },
)
```

---

### 4. 精确刷新

```dart
refresh(ids: ['header']);
```

```dart
EasyConsumer<CounterController>(
  id: 'header',
  builder: (context, controller) {
    return Text('${controller.count}');
  },
)
```

---

### 5. 全局事件通信

#### 定义事件

```dart
class IncrementEvent extends EasyEvent {
  @override
  Type get targetController => CounterController;
}
```

#### 绑定事件

```dart
@override
List<EasyEventBinding> get eventBindings => [
  EasyEventBinding<IncrementEvent>((event) {
    increment();
  }),
];
```

#### 发送事件

```dart
EasyController.broadcast(IncrementEvent());
```

---

## 🔄 生命周期

| 方法           | 说明             |
| ------------ | -------------- |
| initialize() | 初始化 Controller |
| dispose()    | 销毁 Controller  |
| refresh()    | 触发 UI 更新       |

---

## ⚠️ 设计约束

* ❌ 禁止事件多态（必须精确匹配类型）
* ❌ 禁止嵌套同类型 EasyScope
* ✅ Shared 模式需手动 initialize()

---

## 🧠 设计理念

该框架的核心思想：

> **状态 = 数据 + 事件 + 生命周期**

通过事件驱动实现模块间解耦，通过类型系统保证安全，通过局部刷新保证性能。

---

## 📄 License

MIT License

---

# English

## 🚀 Overview

**Easy State Management Framework** is a lightweight, high-performance, strongly-typed state management micro-framework for Flutter.

It focuses on:

* ⚡ O(1) state access
* 🧠 Strong type safety
* 🧩 Event-driven architecture

---

## ✨ Features

* **Event-Driven Architecture** via global EventBus
* **Fine-grained UI updates** using IDs
* **Zero-intrusive design**
* **Strict type safety** (no runtime casting issues)

---

## 📦 Installation

Add to your project:

```yaml
dependencies:
  easy_state: ^1.0.2
```

---

## 🧱 Core Concepts

### 1. EasyController

```dart
class CounterController extends EasyController {
  int count = 0;

  void increment() {
    count++;
    refresh();
  }
}
```

---

### 2. EasyScope (Dependency Injection)

```dart
EasyScope(
  create: () => CounterController(),
  builder: (context, controller) {
    return CounterPage();
  },
)
```

---

### 3. EasyConsumer (Reactive UI)

```dart
EasyConsumer<CounterController>(
  builder: (context, controller) {
    return Text('${controller.count}');
  },
)
```

---

### 4. Fine-grained Refresh

```dart
refresh(ids: ['header']);
```

---

### 5. Global Event System

#### Define Event

```dart
class IncrementEvent extends EasyEvent {
  @override
  Type get targetController => CounterController;
}
```

#### Bind Event

```dart
@override
List<EasyEventBinding> get eventBindings => [
  EasyEventBinding<IncrementEvent>((event) {
    increment();
  }),
];
```

#### Dispatch Event

```dart
EasyController.broadcast(IncrementEvent());
```

---

## 🔄 Lifecycle

| Method       | Description           |
| ------------ | --------------------- |
| initialize() | Initialize controller |
| dispose()    | Dispose controller    |
| refresh()    | Trigger UI rebuild    |

---

## ⚠️ Constraints

* ❌ No event polymorphism
* ❌ No nested same-type EasyScope
* ✅ Shared instances must call initialize()

---

## 🧠 Philosophy

> **State = Data + Events + Lifecycle**

Decoupling via events, safety via types, performance via fine-grained updates.

---

## 📄 License

MIT License
