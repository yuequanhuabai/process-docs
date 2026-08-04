# 字面量联合类型与 enum —— `type X = 'A' | 'B' | 'C'` 是什么

> **触发点**（2026-08-04，Day 16 前端开工前读 `03-完整代码.md`）：
> 「`export type InstanceStatus = 'RUNNING' | 'COMPLETED' | 'TERMINATED'` 这个是啥意思？枚举？」

> 出处：[`../process_instance/03-完整代码.md`](../process_instance/03-完整代码.md) 第 1 节 `src/api/instance.ts`（`:19`）。
> 本篇是 `前端答疑/` 下**第一篇 TypeScript 语言篇**（此前各篇都是 Vue 数据流 / JS 异步）。

---

## 一、先纠误解：不是枚举，而且是**刻意不用**枚举

TS 里真有 `enum` 关键字。同样一件事，本来完全可以写成：

```ts
enum InstanceStatus {
  RUNNING = 'RUNNING',
  COMPLETED = 'COMPLETED',
  TERMINATED = 'TERMINATED',
}
```

写成 `'RUNNING' | 'COMPLETED' | 'TERMINATED'` 是**主动避开了** enum。这个写法的正式名字叫**字符串字面量联合类型**（union of string literal types）。

避开的理由不是风格偏好，是 TS 自己的设计原则逼出来的 —— 见第三节。讲完之后，这个写法不再是「规定如此」，而是「除了这样别无选择」。

---

## 二、机制拆解（纵向剥层）

分三层剥，最后剥到编译产物。

### 第 1 层 · `type X = ...` 不是声明变量，是起别名

它跟 `const` 没有半点关系，跟 Java 的 `class` / `enum` 也不一样 —— 它只是给右边那坨类型取个短名字，**纯粹为了少打字**。

删掉这一行、把所有 `InstanceStatus` 替换成 `'RUNNING' | 'COMPLETED' | 'TERMINATED'`，程序**完全等价**。这是判断「它是不是在定义什么东西」的最快检验：能整体替换掉的，就没定义任何实体。

> Java 里最接近的是……没有。Java 没有类型别名。C 的 `typedef`、Kotlin 的 `typealias` 是同一类东西。

### 第 2 层 · `'RUNNING'` 单独也是一个类型

这是最反直觉的一步，也是理解全篇的关键。

你熟悉的类型是 `String`、`int` 这种。TS 里，**一个具体的值也可以当类型用**：

```ts
let a: string    = '随便什么字符串'   // 类型 string：所有字符串都行
let b: 'RUNNING' = 'RUNNING'          // 类型 'RUNNING'：只能是这一个字符串
b = 'COMPLETED'  // ❌ Type '"COMPLETED"' is not assignable to type '"RUNNING"'
```

想通它的诀窍：**TS 里「类型」的本质是「值的集合」**。

| 类型 | 是哪个集合 | 有几个元素 |
|---|---|---|
| `string` | 所有字符串 | 无穷 |
| `boolean` | `true`、`false` | 2 |
| `'RUNNING'` | 只有 `'RUNNING'` | **1** |
| `never` | 空集 | 0 |

Java 里没有这个概念 —— 你没法写「只能是 `"RUNNING"` 这个值的 String 类型」。这是 TS 与 Java 类型系统最根本的分歧之一（另一个是结构化 vs 名义，见第九节）。

> 顺带解释一个你早晚会问的现象：`boolean` 其实就是 `true | false`，TS 内部真的是这么定义的。所以 `boolean` 不是「基础类型」，它是个联合。

### 第 3 层 · `|` 是集合求并

三个单元素集合并起来，得到一个**恰好三个元素**的集合。所以整行的含义是：

> **这个位置只能填这三个字符串之一，多一个不行、少一个不行、大小写不同也不行。**

### 剥到底 · 编译后它去哪了

**整行原地消失。** `tsc` 的产物里既没有 `InstanceStatus` 这个名字，也没有那三个字符串。运行时**零痕迹、零开销、零可访问性**。

```ts
// 源码
type InstanceStatus = 'RUNNING' | 'COMPLETED' | 'TERMINATED'
const s: InstanceStatus = 'RUNNING'
```
```js
// 编译产物（全部）
const s = 'RUNNING';
```

这就跟 Java 的 enum 彻底分道扬镳了：

| | Java `enum Status` | TS `type Status = 'A' \| 'B'` |
|---|---|---|
| 编译产物 | 一个**真实的类**，三个真实对象 | **什么都不剩** |
| `values()` 遍历 | ✅ | ❌ 没有东西可遍历 |
| `ordinal()` / `name()` | ✅ | ❌ |
| 能进 `EnumMap` / `switch` | ✅ | switch 可以（比字符串），EnumMap 无 |
| 能反射 | ✅ | ❌ |
| 运行时校验非法值 | ✅ 天然 | ❌ **完全不校验** |

最后一行是实战里最要命的差异，第七节会落到本项目。

> **后端视角的准确类比**：TS 这行**不像** Java 的 enum，倒是**很像**你后端 `ProcessInstanceVO.java:17-19` 那三个 `public static final String`。注意你后端当初也**没用** Java enum，用的是 String 常量 —— 两边其实做了同一个取舍（换来跟引擎/JSON 的直接互通，放弃了运行时的类型安全）。

---

## 三、诞生背景 / 设计目的（横向讲史 · 四步）

### 1) 旧世界：裸 JS，状态就是裸字符串

```js
if (row.status === 'RUNING') { /* ... */ }   // 少一个 N
```

**不报错、不崩溃**，只是这个分支永远不执行。JS 没有类型、没有编译期，这行会安安静静地跑到天荒地老。这是最难查的一类 bug —— 没有任何信号，只有「功能好像不生效」。

### 2) 痛点：常量对象只治了一半

社区的第一个对策是常量对象：

```js
const STATUS = { RUNNING: 'RUNNING', COMPLETED: 'COMPLETED', TERMINATED: 'TERMINATED' }

if (row.status === STATUS.RUNING) { }   // ✅ 这个能发现：STATUS.RUNING 是 undefined
function setStatus(status) { }          // ❌ 但这里，谁都能传 'banana' 进来
```

**治住了拼写，治不住取值范围。** 缺的能力是：**在函数签名 / 字段声明上表达「这个位置只准是这几个值之一」**。这件事光靠运行时的对象做不到，必须由类型系统来做。

### 3) TS 的第一版答案是 enum —— 然后它撞了南墙

TS 1.0（2014）直接把 C# 的 `enum` 搬了过来。这非常顺理成章 —— TS 之父 **Anders Hejlsberg 正是 C# 的总设计师**（再往前还有 Turbo Pascal 和 Delphi）。搬来的东西自然带着 C# 的形状。

但 enum 撞上了 TS 给自己立的最高原则：

> **TS = JS + 类型标注。把标注全部擦掉，剩下的必须是能跑的 JS。**

enum 做不到。它**必须生成运行时代码**：

```ts
enum Status { RUNNING = 'RUNNING', COMPLETED = 'COMPLETED' }
```
```js
// 编译产物：凭空多出一个 IIFE 和一个对象
var Status;
(function (Status) {
    Status["RUNNING"] = "RUNNING";
    Status["COMPLETED"] = "COMPLETED";
})(Status || (Status = {}));
```

一个本该属于「类型层」的东西，往产物里塞了一个真实对象。**这在 TS 的自我定位里是越界的** —— 它不再是「标注」，而是在造语言特性。

### 4) 新方案：把这件事完全留在类型层

- **TS 1.4（2015）** 引入联合类型 `A | B`
- **TS 1.8（2016）** 补上字符串字面量类型 `'A'`

两者一拼，`'A' | 'B' | 'C'` 就成立了。它把「取值范围」这件事**完整地表达在类型层**，擦除后一干二净 —— 正好回到原则之内。社区几年之内几乎全倒了过去。

**历史后来给出了裁决。** enum 越来越像个历史包袱：

- `const enum` 想省掉运行时开销，结果跟 Babel、`isolatedModules` 打架（单文件编译时它需要跨文件信息）
- **2024–2025 年 Node 原生支持跑 TS**（`--experimental-strip-types`，实现方式就是字面意义上的「把类型语法整段删掉」），**enum 直接被禁用** —— 它压根不能靠删除来擦除
- **TS 5.8（2025）** 索性加了 `--erasableSyntaxOnly` 开关，专门把 enum 这类「不可擦除语法」全部标红

一个语言特性被自家生态判定为「不该存在」，这在语言史上不多见。**避开 enum 不是个人口味，是主流共识。**

### 5) 代价 / 边界（这条最实用）

字面量联合**没有运行时代表物**。Java 里 `Status.values()` 一把就能遍历出全部成员；TS 这边**做不到** —— 类型编译后就没了，没有东西可遍历。

想在运行时用这几个值（渲染下拉框、做映射表），**只能另外手写一份**。同一组状态因此存在**多份**：类型层一份，运行时按用途各一份。

**这就是不用 enum 换来的账单。** 见第七节，本项目正好是「一份类型 + 两份运行时」。

TS 也提供了把账单压到最小的工具 —— `Record<联合类型, ...>`：它逼着对象的 key 与联合成员**一个不多、一个不少**，漏写立刻编译报错。让类型层去校验运行时那份的完整性，是这套玩法的标准配套。

---

## 四、动手实验

⚠️ **这些在浏览器 console 里验不出来**（类型已被擦除，运行时无痕）。去 [TS Playground](https://www.typescriptlang.org/play) 粘贴，**重点看右侧编译产物**。

```ts
type InstanceStatus = 'RUNNING' | 'COMPLETED' | 'TERMINATED'

// —— 实验 1：正例 vs 反例并排 ——
const a: InstanceStatus = 'RUNNING'   // ✅
const b: InstanceStatus = 'RUNING'    // ❌ 少个 N，编译期就红（旧世界里这行会静默跑一辈子）
const c: InstanceStatus = 'running'   // ❌ 大小写也算不同的值

// —— 实验 2：证明它就是「值的集合」——
let s: 'RUNNING' = 'RUNNING'          // ✅ 单个字面量本身就是合法类型
let t: string = s                     // ✅ 单元素集合 ⊂ 全体字符串，能往上赋
let u: 'RUNNING' = t as string        // ❌ 反过来不行，集合大的塞不进集合小的

// —— 实验 3：Record 的守门作用（自查清单那题的答案）——
const MAP: Record<InstanceStatus, string> = {
  RUNNING: '进行中',
  COMPLETED: '已办结',
}                                     // ❌ Property 'TERMINATED' is missing

// —— 实验 4（看点在这）：把上面第一行改成 enum，再看右侧 ——
// enum InstanceStatus { RUNNING = 'RUNNING', COMPLETED = 'COMPLETED', TERMINATED = 'TERMINATED' }
```

**实验 4 是全篇的记忆点**：`type` 那版右侧产物只有几个 `const`；换成 `enum` 后凭空多出一坨自执行函数。**一眼看见「谁擦得掉、谁擦不掉」** —— 第三节讲的整段历史，就压在这个画面里。

**实验 5（反直觉，值得跑）**：类型不参与运行时校验。

```ts
const raw = JSON.parse('{"status":"banana"}')  // 模拟后端返回了非法值
const vo: { status: InstanceStatus } = raw     // ✅ 竟然不报错！
console.log(vo.status)                          // 'banana'
```

`JSON.parse` 返回 `any`，类型检查在这里**整个失效**。这就是第六节最后一行的来源 —— **网络边界是 TS 的盲区**。

---

## 五、常见误解速查表

| 误解 | 实际 |
|---|---|
| 它是枚举 | 是联合类型。TS 的 `enum` 是另一个东西，这里**刻意不用** |
| 它定义了三个常量 | **没定义任何东西**，编译后整行消失 |
| 可以写 `InstanceStatus.RUNNING` | ❌ 不行，它不是对象。只能直接写字符串 `'RUNNING'` |
| 可以遍历出三个值 | ❌ 不行，所以才要手写 `STATUS_MAP` / `statusOptions` |
| `export` 了就说明它有实体 | ❌ `export type` 导出的是纯类型，产物里没有对应的 export |
| 运行时会校验后端返回值 | ❌ **不会**。后端真返回 `'banana'`，TS 拦不住 |

---

## 六、回到本项目

### 定义与三处用法

| 位置 | 用法 |
|---|---|
| `process_instance/03-完整代码.md:19` | 定义 |
| 同上 `:32` | `ProcessInstance` 接口的 `status` 字段类型 |
| 同上 `:260` | `Record<InstanceStatus, {...}>` 声明 `STATUS_MAP` —— **让类型层守住映射表的完整性** |
| 同上 `:266` | `statusOptions` 下拉数组 |

### 「一份类型 + 两份运行时」的账单

第三节第 5 步说的代价，在这一页看得见摸得着：同一组状态存在**三份**

1. **类型层**：`InstanceStatus`（`:19`）
2. **运行时 ①**：`STATUS_MAP`（`:260`）—— 表格标签的文字与颜色
3. **运行时 ②**：`statusOptions`（`:266`）—— 筛选下拉的选项

其中第 2 份被 `Record<InstanceStatus, ...>` 焊死了，漏写会报错；**第 3 份没有**。

> ⚠️ **第 3 份是三份里唯一失守的**：`statusOptions` 首项是 `{ value: '', label: '全部状态' }`，而 `''` **不属于** `InstanceStatus`，所以这个数组没法声明成 `InstanceStatus[]`，TS 管不到它。将来后端加第四种状态，`STATUS_MAP` 会报错提醒你，**`statusOptions` 不会** —— 下拉框会安静地少一项。修法见第八节的 `as const`。

### 与后端的呼应

| 层 | 位置 | 形态 |
|---|---|---|
| 后端常量 | `ProcessInstanceVO.java:17-19` | 三个 `public static final String`（**也没用 Java enum**） |
| 后端产出 | `ProcessInstanceVO.java:92-97` `statusOf()` | 按 `endTime` + `deleteReason` 穷举三分支算出来 |
| 后端消费 | `ProcessInstanceServiceImpl.java:146-161` `applyStatusFilter()` | if/else 比字符串，未知值抛 `BizException` |
| 前端类型 | `03-完整代码.md:19` | 字面量联合 |

**四处的字面值必须严格一致，任何一处改了都要同步另外三处。** 两边都没有编译器帮忙对齐 —— 后端是 String 常量、前端是擦除后的类型，中间隔着 JSON。这是纯人工纪律。

### 这一页实际安不安全

`STATUS_MAP[row.status]` 若拿到 `undefined`，会炸在后面的 `.text` 上（实验 5 演示的正是这条路）。

**实际安全** —— 但**安全来自后端**：`statusOf()` 是穷举三分支的，产不出第四种值。**不是来自那行 TS。** 分清这一点很重要：TS 的保护到 HTTP 边界为止，边界另一头靠的是后端实现的严谨。

---

## 七、一句话总结

`type X = 'A' | 'B' | 'C'` 是**一张只存在于编译期的白名单**：把「这个位置只准填这几个字符串」写进签名，让拼写错误在编译期就红；代价是运行时它什么都不留，需要遍历时得自己另备一份。

---

## 八、往下可以再挖的

1. **`as const`（TS 3.4）** —— 反过来从**运行时数组推导出类型**，能把上面的「三份」压成一份，也正好补上 `statusOptions` 失守的那个口子。是本篇最直接的续集。
2. **可辨识联合（discriminated union）** —— 本篇的进阶形态：联合的不是字符串而是对象，靠一个公共字段分辨。Day 18 历史页做「不同结局展示不同字段」时会撞上。
3. **类型收窄（narrowing）** —— `if (s === 'RUNNING')` 之后 TS 为什么知道 `s` 只剩一种可能；`switch` 穷举后配合 `never` 做「漏一个分支就编译报错」。
4. **结构化类型 vs 名义类型** —— 为什么 TS 里两个字段相同的 interface 能互相赋值，Java 里不行。是 TS 与 Java 类型系统的另一个根本分歧（第二节提过）。
5. **边界校验（zod / valibot）** —— 实验 5 那个洞的正经修法：在 HTTP 边界做一次运行时校验，让类型与现实重新对齐。
