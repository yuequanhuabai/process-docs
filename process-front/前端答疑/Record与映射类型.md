# `Record<string, unknown>` 是什么 —— 兼谈它和后端 `Map` 的关系

> **触发点**（2026-08-04，Day 16 前端开工前读 `03-完整代码.md`）：
> 「`StartInstanceBody` 对象里的 `Record<string, unknown>` 是什么意思？和后端的 `Map` 有什么关系，等价？」

> 出处：[`../process_instance/03-完整代码.md`](../process_instance/03-完整代码.md)`:41`；对应后端 `StartProcessInstanceRequest.java:20` 的 `Map<String, Object> variables`。
> 本篇是 `前端答疑/` **第三条链（TypeScript）第 3 篇**，接 [`字面量联合类型与enum.md`](./字面量联合类型与enum.md)、[`null与undefined.md`](./null与undefined.md)。

---

## 📖 怎么读这一篇

**第一次读不懂是正常的**，本篇比前两篇抽象（涉及「用类型生成类型」这一层）。建议分两次读：

| 什么时候 | 读哪几节 | 为什么 |
|---|---|---|
| **现在（Day 16 写代码）** | **第零节** + **第四节（那个坑）** | 够你把这一页写对，不需要理解机制 |
| **将来（P6 表单设计器）** | 全篇，重点第七节 ② | 那时你要**亲手**把开放的键收紧成封闭的，机制那层绕不过去 |

第二、三节是原理，看不透先放着 —— 它不影响你写对代码。

---

## 零、最短回答（不需要理解机制的版本）

三句话：

1. **`Record<string, unknown>` = 一个普通的 JS 对象 `{ }`**，键随便写，值什么都行。
   写代码时就写 `{ reason: '事假' }`，跟平时写对象一模一样。

2. **和后端 `Map<String, Object>` 在 JSON 线上等价**，语言层不是一回事。
   ```
   前端 { reason: '事假' } → JSON {"reason":"事假"} → 后端 HashMap<String,Object>
                                 ↑ 等价只发生在这里
   ```

3. **⚠️ 千万别因为后端叫 Map 就写 `new Map()`** —— JS 也有个 `Map` 类，但它 `JSON.stringify` 出来是 `{}`，**数据会静悄悄全丢，还不报错**。详见第四节。

第 3 条是本篇唯一「现在就必须记住」的东西。

---

## 一、先纠误解：「等价」对了一半

问题问的是「等价？」。准确答案是：**在 JSON 线上等价，在语言层三处不同。**

| | 后端 `Map<String, Object>` | 前端 `Record<string, unknown>` |
|---|---|---|
| 是什么 | **运行时的真实容器**（`HashMap` 实例，有 `put`/`get`/`size`） | **编译期的一句类型描述**，编译后消失 |
| 描述的东西 | 一个 Map 对象 | 一个**普通对象字面量** `{ }` |
| 值类型 | `Object`：能直接调 `toString()` 等 | `unknown`：**一个成员都不能碰**，必须先收窄 |

两边只是各自用本地语言表达了同一个意思 ——「一包不定形的键值对」—— 然后**在网线上会合**。

---

## 二、机制拆解（纵向）：`Record` 根本不是语法

> 本节是原理，第一次看不透可跳过。

### 第 1 层 · 它是标准库里的一个工具类型

`Record` **不是 TS 关键字**，是标准库 `lib.es5.d.ts` 里写出来的一行普通代码：

```ts
type Record<K extends keyof any, T> = { [P in K]: T }
```

跟你自己写 `type X = ...` 是同一种东西（见第一篇第二节：`type` 只是起别名）。它只是被内置了，所以不用 import。

### 第 2 层 · `[P in K]` 是「对集合里每个成员生成一个字段」

这是全篇最抽象的一步，叫**映射类型**。读法：

> 对 K 这个集合里的**每一个**成员 P，生成一个 `P: T` 的字段。

拿你们自己的代码代进去看，一下就具体了 —— `03:260` 那个：

```ts
Record<InstanceStatus, string>
// K = 'RUNNING' | 'COMPLETED' | 'TERMINATED'   ← 3 个成员的集合
// 于是逐个生成 3 个字段，展开后 ≡
{
  RUNNING: string
  COMPLETED: string
  TERMINATED: string
}
```

**这就是为什么 `STATUS_MAP` 漏写一个键会编译报错** —— 展开后那 3 个字段都是必填的。第一篇第三节说的「让类型层守住映射表的完整性」，机制就在这。

> 回想第一篇的核心：**类型 = 值的集合**。`InstanceStatus` 是个 3 元素集合，所以 `[P in K]` 循环 3 次。这里两篇接上了。

### 第 3 层 · K 换成 `string` 会发生什么

```ts
Record<string, unknown>
// K = string = 所有字符串的集合（无穷大）
// 展开后 ≡
{ [key: string]: unknown }     // 这个写法叫「索引签名」
```

对无穷集合做「逐个生成字段」，结果就是「**任意键都合法**」—— 等于没有约束。

### 一张表看懂：同一个 Record，两种脾气

| 位置 | 写法 | K 是几元集合 | 效果 |
|---|---|---|---|
| `03:260` | `Record<InstanceStatus, {...}>` | **3** | **键封闭**：必须写全，漏一个报错 |
| `03:41` | `Record<string, unknown>` | **∞** | **键开放**：随便写，不校验 |

> **`Record` 本身没有"严"或"松"，严松完全由 K 决定。** 这是本篇最值钱的一句话 —— 第七节 ② 讲 P6 要做什么，全靠它。

### 剥到底

编译后整段消失。运行时 `{ reason: '事假' }` 就是个普通对象，没有任何 Record 的痕迹。跟前两篇一个道理。

---

## 三、`unknown` 不是 Java 的 `Object`

### 差在哪

```ts
let a: any     = x;   a.foo.bar()      // ✅ 编译器放行，运行时炸
let u: unknown = x;   u.foo            // ❌ 编译期就拦：'u' is of type 'unknown'
                      if (typeof u === 'string') u.length   // ✅ 收窄之后才能用
```

**Java 的 `Object` 至少能直接调 `toString()` / `equals()` / `hashCode()`**（万物继承 Object）。TS 的 `unknown` **一个成员都碰不了**。它比 Java 的 Object 更严。

心智模型倒是对得上：

| | Java `Object` | TS `unknown` |
|---|---|---|
| 装进去 | 直接装，接受一切 | 直接装，接受一切 |
| 取出来用 | `instanceof` 判断 + **强制转型** | `typeof` / `in` 判断，**自动收窄，不用转** |
| 判断发生在 | **运行时**（有开销，可能抛 `ClassCastException`） | **编译期**（零运行时代价，也零运行时保护） |

### 为什么不写 `any`（横向一小段）

TS 早期只有 `any`。`any` 是逃生舱，但它**有传染性** —— 任何 any 参与的表达式结果还是 any，类型安全从那一点开始整片塌陷。

根子上是它把两件事混为一谈了：

- 「我**不知道**这是什么」—— 合理，但下游必须先检查
- 「我**不想管**这是什么」—— 放弃治疗

**TS 3.0（2018）加入 `unknown`**，专门承担第一件事：赋值端和 `any` 一样宽，使用端却极严。代价是要多写收窄代码，但那个收窄本来就该写。

Java 里没有这个区分 —— `Object` 一个词同时扮演两个角色，没得选。**这是 TS 比 Java 表达力强的又一处**（上一篇是 null/undefined 之分）。

---

## 四、⚠️ 那个坑（本篇唯一必须现在记住的）

JS **确实有**一个 `Map` 类（ES6 引入）。看到后端是 `Map<String,Object>`，非常容易顺手写成：

```ts
variables: new Map([['reason', '事假']])   // ❌ 灾难
```

后果：

```js
JSON.stringify(new Map([['reason', '事假']]))   // '{}'   ← 全没了！
```

**`JSON.stringify` 序列化 `Map` 得到空对象。** 请求体变成 `{"variables":{}}`，流程变量全空，**而且前后端都不报任何错**：后端老老实实收到一个空 HashMap，流程照常发起，只是变量丢了。要等到审批节点读不到 `reason` 才暴露。

原因：`JSON.stringify` 只序列化对象**自身的可枚举属性**，而 `Map` 的数据存在内部槽（internal slot）里，不是属性。同理 `Set`、`Date` 之外的多数内置对象都有各自的序列化怪癖。

> **记牢**：`Record<string, unknown>` 描述的**必须**是对象字面量 `{ }`，跟 JS 的 `Map` 类**毫无关系**。
> TS 里真要用 `Map` 类，类型写作 `Map<string, unknown>` —— **只差一个 `Record` 前缀，含义天差地别。** 这两个名字长得太像，是这一处最容易出事的地方。

（JS 的 `Map` 有它的正当用途：键可以是任意类型不限于字符串、保证插入顺序、有 `.size`。但**凡是要过 JSON 的地方一律用普通对象**。）

---

## 五、动手实验

**实验 1 · 那个坑，亲眼看一次**（浏览器 console，**这个必须跑**）：

```js
const obj = { reason: '事假' }
const map = new Map([['reason', '事假']])
console.log(JSON.stringify({ variables: obj }))   // {"variables":{"reason":"事假"}}  ✅
console.log(JSON.stringify({ variables: map }))   // {"variables":{}}                 ❌ 静悄悄全丢
```

**"咦？"落在第二行** —— 没有报错、没有警告，数据就是没了。

**实验 2 · 同一个 Record，两种脾气**（TS Playground，验证第二节那张表）：

```ts
type Status = 'RUNNING' | 'COMPLETED'
const closed: Record<Status, string> = { RUNNING: 'a' }      // ❌ 漏了 COMPLETED
const open:   Record<string, string> = { 随便什么键: 'a' }    // ✅ 全放行
```

对照跑一遍，第二节的原理不用背也记住了。

**实验 3 · 证明 Record 就是索引签名**：

```ts
type A = Record<string, unknown>
type B = { [key: string]: unknown }
const x: A = { reason: '事假' }
const y: B = x        // ✅ 互相赋值毫无障碍，说明是同一个类型
```

**实验 4 · `unknown` 与 `any` 的分水岭**：

```ts
const raw: unknown = JSON.parse('{"days":3}')
raw.days                                    // ❌ 编译期拦下
;(raw as { days: number }).days             // ✅ 你自己担保
if (typeof raw === 'object' && raw !== null && 'days' in raw) raw.days   // ✅ 正经收窄

const bad: any = JSON.parse('{"days":3}')
bad.days.toFixed().whatever.explode()       // ✅ 编译器全程放行，运行时炸
```

---

## 六、常见误解速查表

| 误解 | 实际 |
|---|---|
| `Record` 是 TS 关键字 | ❌ 是标准库里一行普通的 `type`，用映射类型写的 |
| `Record<string,unknown>` 对应 JS 的 `Map` | ❌ **对应普通对象 `{ }`**。JS 的 Map 是 `Map<string,unknown>`，差一个前缀 |
| 后端是 Map，前端也该 `new Map()` | ❌ **会静默丢数据**，见第四节 |
| `Record` 比索引签名更严格 | ❌ `Record<string,T>` 和 `{[k:string]:T}` 完全等价；严不严看 K |
| `unknown` 就是 `any` 换个名 | ❌ 赋值端一样宽，**使用端天差地别** |
| `unknown` 等于 Java 的 `Object` | ❌ 比 Object 更严，连 `toString()` 都不让直接调 |
| 写了 `Record<string,unknown>` 就有类型保护 | ❌ 键开放 = 拼错不报错，见第七节 ② |

---

## 七、回到本项目

### ① `unknown` 比 Flowable 的真实约束宽得多

Flowable 存变量时要往 `ACT_RU_VARIABLE` / `ACT_HI_VARINST` 的 `TYPE_` 列挑一个类型（string / long / double / boolean / date / serializable / json…），**不是什么都能存**。塞个复杂对象进去会走 serializable 分支，历史表里变成一坨二进制，查询和展示全废。

后端 DTO 的注释已经写了（`StartProcessInstanceRequest.java:18-19`）：

> 「值建议用 string/number/boolean 基本类型」

**注意是「建议」—— 它是注释，不是约束。** `unknown` 和 `Object` 谁都表达不出「只能是这几种标量」，真正的约束在引擎里，两边的类型系统都够不着。

**这是第三条链的老主题了**：第 1 篇是后端返回非法 status 拦不住，第 2 篇是 `| null` 只是手抄的承诺，这篇是「值类型的真实约束在第三方引擎里」。**TS 的保护到 HTTP 边界为止。**

### ② 键开放 = 拼错不报错 —— 这是 P6 要治的病 ⭐

`03:355` 那条注释：

> 「变量名是弱契约：引擎不校验拼写，写错会悄悄新建一个变量」

**`Record<string, unknown>` 里那个 `string` 就是这个「弱」在类型层的体现。** 键是开放集合，所以你写 `{ resaon: '事假' }`（少个 a）——

- TS 放行（`string` 键，什么都合法）
- 后端放行（`Map<String,Object>`，什么都能装）
- 引擎放行（高高兴兴新建一个叫 `resaon` 的变量）

然后审批节点读 `reason` 读到 null。**三道关卡，一道都拦不住。**

跟 `:260` 那个 `Record<InstanceStatus, ...>` 一对比就特别清楚：

> **把 K 从无穷集换成有限集，拼写错误立刻从「运行时静默」变成「编译期报错」。**

**P6 表单设计器要做的事，本质就是这个替换** —— 用表单定义生成一个封闭的键集合，把 `Record<string, unknown>` 收紧成 `Record<'reason' | 'days', ...>` 之类。到那时回头看第二节的映射类型，就不是抽象概念而是手上的工具了。

> 顺带：`测试进度断点.md` 第二节提到的「多级审批 `comment` 变量互相覆盖」也是同一个病根 —— 键是开放的、实例级变量只有一份，谁后写谁赢。治理点同样在 P6。

### ③ `:356` 那行是上一篇的直接应用

```ts
variables: form.reason.trim() ? { reason: form.reason.trim() } : undefined,
```

没填就整个键不发送 —— 对应 [`null与undefined.md`](./null与undefined.md) 场景 2。

若写成 `{}` 会发个空对象（无害但多余）；若写成 `null`，Jackson 反序列化成 null 的 Map，`startProcessInstanceByKey` 收 null 也能跑 —— **三种写法这里恰好都不炸，但语义上只有 `undefined` 是准确的**。

---

## 八、一句话总结

`Record<string, unknown>` 是标准库里一个**映射类型工具**，展开就是索引签名 `{ [k: string]: unknown }`，描述的是**普通对象字面量**；它和后端 `Map<String,Object>` **只在 JSON 线上等价**，语言层三处不同 —— Record 编译后消失、`unknown` 比 `Object` 更严、**而且它跟 JS 的 `Map` 类毫无关系（那个 `JSON.stringify` 会变成 `{}`）**。

**`Record` 的严松全看 K 是多大的集合** —— 这一句是 P6 表单 schema 的地基。

---

## 九、往下可以再挖的

1. **映射类型的修饰符** —— `[P in K]?:` 加问号、`readonly [P in K]`、`-?` 去掉可选。`Partial<T>` / `Required<T>` / `Readonly<T>` 全是这么写出来的，都只有一行。
2. **`keyof` 与 `typeof`（类型位置的）** —— 从一个对象**反推**出它的键集合，是 ② 里「用表单定义生成封闭键集合」的关键一步。
3. **索引签名 vs `Record` 的细微差别** —— 在 `interface` 里两者的可扩展性不同（`interface` 不能直接用 Record 做整体形状）。
4. **边界校验（zod / valibot）** —— 本链的收口，① 那个洞的正经修法。
