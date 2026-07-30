# @change 事件（答疑笔记）

> 由答疑 CLI 整理。通用前端原理。触发点：@change 是监控 v-model 变化吗？还是别的？诞生背景？
> 关联：`v-model双向绑定.md`、`props向下events向上.md`。

## 先纠正最大的误解

> **@change 不是在"监控 v-model"，它监控的是一个叫 "change" 的事件。**

`@` 是 `v-on:` 的简写。`@change="handler"` = **"监听 change 这个事件，触发时执行 handler"**。它的机制是**订阅事件**，不是盯着某个变量。

## v-model 与 @change 是两套独立的东西

```html
<el-switch v-model="latestOnly" @change="handleLatestChange" />
```

| | 监听对象 | 干什么 |
|---|---|---|
| `v-model` | 组件发出的 `update:modelValue` 事件 | 把新值同步回变量 |
| `@change` | 组件发出的 `change` 事件 | 值变了之后跑你的逻辑 |

两者只是**碰巧都在开关被拨动时触发**，是"两个事件被同一个用户动作同时点燃"，彼此没有从属关系。可以只写 v-model 不写 @change，反之亦然。

## 它监控 v-model，还是其它变化都监控？

**都不是——只监控 "change" 这一个特定事件，别的事件一概不管。**
- 点鼠标 → `@click`；获得焦点 → `@focus`；失去焦点 → `@blur`；输入 → `@input`。
- 每种交互是**不同名字的事件**，@change 只捕获名为 change 的那个，不会因 hover/focus 触发。

**"change" 何时发出？由组件自己定义：**
- `el-switch`：值被拨动、真正变化时发。
- `el-input`：`change` 在**失焦且值变了**时才发；`input` 事件是**每敲一个字**就发。同一控件两者时机完全不同。

## 诞生背景：来自原生 DOM

`change` 不是 Vue 发明的，继承自浏览器**原生 DOM 事件**。没框架的年代 HTML 就有 `<input onchange="...">`。原生里 change 与 input 的分工早已存在：
- `input`：值一变**立即**触发（每次击键）。
- `change`：值**确定下来**才触发（失焦/选定/勾选）。

设计目的：有些场景要实时响应（搜索边打边搜 → input），有些要等"改完了"再响应（避免每敲一下发请求 → change）。
Vue 沿用这套约定：原生标签上 @change 就是原生 change；组件（el-switch）上是组件作者**故意起名 "change"** 的自定义事件，为了用起来跟原生一样熟悉。

## 设计目的：关注点分离

为什么不把逻辑塞进 v-model，非要另开 @change？为了分开两件事：
- **v-model 管"状态同步"**：保证 `变量 === 控件值`，纯数据层、无副作用。
- **@change 管"响应副作用"**：值变了要顺带干的事（发请求、重查、校验、联动）。

本项目：
```html
<el-switch v-model="latestOnly" @change="handleLatestChange" />
```
```ts
function handleLatestChange() {
  current.value = 1   // 回第一页
  loadList()          // 重新查列表 ← 副作用
}
```
v-model 已把新值存进 latestOnly；但"存好值"≠"要重查"。要不要触发查询是业务副作用，交给 @change。分工让数据同步和业务逻辑互不污染。

## 对比 watch：真正"监控变量本身"的是它

要"只要变量变了就响应、不管谁改的"，用的不是 @change，而是 `watch`：
```ts
watch(latestOnly, () => { loadList() })  // 任何途径改 latestOnly 都触发，包括代码里赋值
```

| | 触发来源 | 程序里改值会触发吗 |
|---|---|---|
| `@change` | 组件发出的事件（通常**用户操作**引起） | 一般**不会**（代码直接改变量不经过控件事件） |
| `watch` | 盯着**响应式变量本身** | **会**，任何途径的改变都触发 |

这里选 @change 而非 watch，是因为只关心"用户拨开关"这个动作，不理会程序内部对 latestOnly 的赋值。

## 一句话总结

> `@change` = `v-on:change`，**订阅组件发出的 "change" 事件**（不是监控 v-model，也不监控其它事件）；何时发 change 由组件定义；源自原生 DOM 的 change 事件；设计目的是把"状态同步"（v-model）和"变化后的副作用"（@change）分开。要监控变量本身的任意变化，那是 `watch` 的活。
