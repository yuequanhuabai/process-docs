# props 向下、events 向上（答疑笔记）

> 由答疑 CLI 整理。通用前端原理，Vue 组件协作的**总纲**。
> `v-model`、`@change`、`:data`、插槽都是它的具体表现。
> 关联：`v-model双向绑定.md`、`change事件.md`、`何时抽组件.md`、`插槽slot与作用域插槽.md`。

## 问题：组件是一棵树

Vue 把界面拆成组件，层层嵌套成树。以流程管理页为例：
```
index.vue（父，拥有数据）
├── el-table       （子）
│   └── el-tag     （孙）
├── el-switch      （子）
└── el-pagination  （子）
```
父子怎么传数据、通信？若谁都能随便改谁的数据，深层组件偷偷改顶层状态，出 bug 无从追查。于是 Vue 定了铁律管住数据流向——**props 向下、events 向上**。

## 两条规则

**规则一：props 向下（父 → 子，传数据）**
父通过 **props** 把数据传给子，子被动接收、负责显示：
```html
<el-table :data="list" />
<el-tag :type="row.suspended ? 'info' : 'success'" />
<el-pagination :total="total" :current-page="current" :page-size="size" />
```
`:xxx`（`v-bind:` 简写）就是往下递 props。数据像水一样从上往下流。

**规则二：events 向上（子 → 父，报告变化）**
子**不能直接改**父给的数据（props 只读，改了会警告）。要变，就**发事件"喊"给父，让父自己改**：
```html
<el-pagination @current-change="handlePageChange" />
<!-- 用户点第2页 → 分页喊 current-change → 父的 handlePageChange 改 current 再重查 -->
```
`@xxx`（`v-on:` 简写）是父在听子发上来的事件。通知像信号从下往上冒。

## 核心原则：为什么单向

1. **单一数据源**：数据只住在拥有它的组件里（这里是 index.vue）。子手里的只是父传下的副本，不是本体。
2. **props 只读、子不许私改**：要变必须发事件请父来改，"谁能改数据"被限制在数据主人手里。
3. **数据流可追踪**：任何变化都发生在主人那里，出问题只盯主人组件，方向固定 = 可预测 = 好调试。

> 后端类比：
> - props 向下 ≈ **方法传参**（参数应只读，不反向篡改调用方字段）。
> - events 向上 ≈ **回调 / 返回值 / 发事件**（子干完活通知父，不直接改父的成员变量）。
> - 整体 ≈ 避免共享可变全局状态，改用"传入不可变参数 + 通过事件通信"。

## v-model 其实就是这个模型的糖

```html
<el-switch v-model="latestOnly" />
```
展开：
```html
<el-switch
  :model-value="latestOnly"                    // ① props 向下：把值传给开关
  @update:model-value="v => latestOnly = v"    // ② events 向上：开关喊"我变了"，父自己回写
/>
```
即便"双向绑定"，底层仍**严格单向**：值从不自动往上流，永远是子**显式发事件**、父**显式更新**。"父拥有数据"这条不变量始终成立。@change 是同一次上报里另一个并行事件，专挂副作用。

## 把整页串成闭环

```
   父 index.vue 拥有状态（list / current / latestOnly / loading）
                │
   ① props 向下  │  :data / :total / :current-page / v-model
                ▼
   子组件渲染界面（表格、分页、开关）
                │
   ② 用户操作     │  拨开关 / 点第2页 / 点删除
                ▼
   ③ events 向上  │  @change / @current-change / @click
                ▼
   父的 handler 改自己的状态（current=2 → loadList()）
                │
                └──► 状态一变，新 props 再向下流，界面自动重渲染 ↺
```
数据永远顺时针单向转，没有任何一步是子组件绕过父直接改数据。这是整个 Vue 应用的运转骨架。

## 一句话总结

> **props 向下、events 向上** = 数据只住在主人组件、通过 props 只读地往下传，子想改就发事件往上报、由主人来改。目的是**单一数据源 + 单向可追踪的数据流**。`v-model`/`@change`/`:data`/插槽全是它的招式，连"双向绑定"也搭在这条单向规则之上。
