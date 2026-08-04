# `null` 与 `undefined` —— 什么时候写 `| null`，什么时候写 `?:`

> **触发点**（2026-08-04，Day 16 前端开工前读 `03-完整代码.md`）：
> 「`ProcessInstance` 对象里面的属性字段，为什么有些是 `string`，有些却多了 `null` 呢？我没记错的话，还有一个 `undefined`，这个的应用场景是什么？」

> 出处：[`../process_instance/03-完整代码.md`](../process_instance/03-完整代码.md) 第 1 节 `src/api/instance.ts`。
> `undefined` 在那份文档里出现 7 次：`:40`、`:41`、`:49`、`:57`、`:70`、`:353`、`:356`。
> 本篇是 `前端答疑/` **第三条链（TypeScript）第 2 篇**，接 [`字面量联合类型与enum.md`](./字面量联合类型与enum.md)。两篇共用同一条主线：**TS 的保护到 HTTP 边界为止。**

---

## 一、先纠误解：不是随手写的，是**方向**决定的

问题里藏着一个隐含前提——「这几种写法是不是有点随意」。恰恰相反，它们分得很死：

| 写法 | 含义 | 只出现在 |
|---|---|---|
| `id: string` | 这个字段**一定有值** | 两边都有 |
| `endTime: string \| null` | 字段**在**，但值可能是 `null` | **响应**对象 |
| `businessKey?: string` | 字段**可能根本不存在** | **请求**对象 |

关键分野在后两行：

> **`null` = 有格子，格子空着；`undefined` = 压根没这个格子。**

而选哪个，由**数据流方向**决定，不由个人口味决定：

- **`ProcessInstance`（后端 → 前端，响应）** —— 全篇只用 `| null`，**一个 `?:` 都没有**
- **`StartInstanceBody`（前端 → 后端，请求）** —— 全篇只用 `?:`，**一个 `| null` 都没有**

这个「方向律」的根据在第四节第 2 条（JSON 的不对称），那是全篇最硬的一条推理。

---

## 二、机制拆解（纵向）

### 两者在语言层是能区分开的

```js
const a = { x: null }
const b = {}

a.x             // null
b.x             // undefined   ← 属性不存在，读了不报错，给你个 undefined

'x' in a        // true    ← 格子在
'x' in b        // false   ← 格子不在

Object.keys(a)  // ['x']
Object.keys(b)  // []
```

**`in` 和 `Object.keys` 就是分水岭。** 如果两者只是「都表示空」，这两个操作不会有差别 —— 它们有差别，说明这是两件事。

### 判等的坑（写代码天天撞）

```js
null == undefined    // true   ← 宽松相等：故意设计成"两个空互相相等"
null === undefined   // false  ← 严格相等：类型都不同
typeof null          // 'object'      ← 1995 年的 bug，见第三节
typeof undefined     // 'undefined'
```

**实用推论**：`x == null` 这一个写法能同时判掉 null 和 undefined。这是 ESLint 的 `eqeqeq` 规则唯一放行 `==` 的场景（`allowNull` 选项），也是老代码里满地 `== null` 的原因。

### Java 对照（差得最远的地方）

**Java 只有 `null`，没有第二个空值。** 所以：

```java
map.get(k)   // 返回 null —— 是"key 不存在"还是"value 本来就是 null"？分不清
map.containsKey(k)   // 只能再查一次
```

JS 把这两件事**在语言层面分开了**：属性不存在给 `undefined`，属性存在但为空给 `null`。**这是 JS 少数比 Java 表达力强的地方**，也是后端背景的人最容易忽略的一处差异——习惯了「空就是 null」，会看不出 `?:` 和 `| null` 在说两件不同的事。

---

## 三、诞生背景（横向四步）

### 1) 旧世界：抄 Java，只有 `null`

1995 年 Brendan Eich 十天写出 JS，当时的政治任务是「**看起来像 Java**」。`null` 就是直接从 Java 搬来的。

### 2) 痛点：有一类「空」不是程序员写的

很快发现 `null` 不够用。有一类空是**引擎自己撞上的**，程序员根本没参与：

```js
let x;                          // 声明未赋值 → 引擎得给个什么
({}).foo                        // 属性不存在 → 得返回个什么
(function(){})()                // 函数没 return → 得返回个什么
(function(a){ return a })()     // 参数没传 → a 是什么
```

这四种情况引擎**必须**拿出一个值来。但如果都用 `null`，就跟「程序员主动置空」混在一起了 —— 你再也分不清 `obj.foo === null` 是「后端明确告诉我这是空的」还是「压根没这个字段」。

### 3) 新方案：拆成两个，按「谁给的」划分

> **`undefined` = 系统给的空**（"我没找到" / "还没有"）
> **`null` = 人给的空**（"我明确告诉你这里是空的"）

上面那四种情况全归 `undefined`，`null` 留给显式赋值。这个划分本身是站得住的。

### 4) 代价：JS 从此背上双空值系统

三十年来所有 JS 程序员都在给它擦屁股 —— `== null` 的特例、可选链 `?.`、空值合并 `??`，全是为了应付「有两个空」这件事而生的语法。**Eich 本人后来公开说过，如果能重来只会留一个。**

留到今天的化石证据：

```js
typeof null   // 'object'   ← 明确承认的实现 bug
```

修不掉了 —— 改它会把全世界依赖这个行为的网页搞崩。这是「向后兼容压倒一切」在 JS 里最著名的一例。

### 5) TS 这一层：`| null` 是 2016 年才必须写的

早期 TS 跟 Java 一样，`null` 和 `undefined` 是**所有类型的子类型**：

```ts
let s: string = null   // 早期 TS：完全合法，类型系统对空指针零防护
```

**TS 2.0（2016）引入 `strictNullChecks`**：开启后 `string` 就真的只能是字符串，想允许空**必须显式写出来**。业界共识是「不开等于白用 TS」——它把 Java 里那个价值十亿美元的错误（Tony Hoare 语）在编译期挡住了。

**本项目 `process-front/tsconfig.app.json:26` 是 `"strict": true`**（含 `strictNullChecks`）。所以：

> `endTime: string | null` 里的 `| null` **不是可写可不写的注释，是必须写的**。
> 不写的话 `row.endTime` 拿到 null 时 TS 不会警告，直接 `.slice()` 就炸。

---

## 四、`undefined` 的四个应用场景

按实用度排。**第 2 条是全篇的题眼。**

### 场景 1 · 可选字段 / 可选参数（`?:`）

```ts
businessKey?: string    // ≈ businessKey: string | undefined，外加"可以整个不写这个键"
```

`ProcessInstance` 里一个 `?:` 都没有 —— 因为**后端一定会把所有字段都给出来**（值可能是 null，但键一定在）。
`StartInstanceBody`（`:38-42`）全是 `?:` —— 因为发起流程时业务键和变量都可以不传。

### 场景 2 · JSON 的不对称 ⭐

```js
JSON.stringify({ a: null })       // '{"a":null}'   ← 键还在
JSON.stringify({ a: undefined })  // '{}'           ← 键整个消失！
```

**JSON 规范里根本没有 `undefined` 这个东西。** 由此推出两条硬结论，「方向律」就是从这来的：

| 方向 | 推论 |
|---|---|
| **响应**（后端 → 前端） | JSON 里**不可能**出现 undefined → `ProcessInstance` 只能用 `\| null`，写 `?:` 是错的 |
| **请求**（前端 → 后端） | 字段设为 undefined = **这个字段不发送** → 用 `?:` 表达"可以不传" |

第二条正是 `:353` 那行的全部意义：

```ts
businessKey: form.businessKey.trim() || undefined,   // 用户没填 → 键根本不出现在请求体里
```

写成 `|| null` 的话，后端会收到 `{"businessKey": null}`。有些框架会把它当成**显式置空**（区别于「不传」），语义就跑偏了。`:356` 的 `variables` 同理。

### 场景 3 · axios 的 params 过滤（`:49`、`:57`、`:70`）

```ts
params: { current, size, definitionKey: definitionKey || undefined }
```

axios 拼 query string 时**跳过 `undefined` 的键**，但**空串会老老实实拼出去**：

| 传入值 | 拼出来的 URL |
|---|---|
| `undefined` | `?current=1&size=10` ← 键消失 ✅ |
| `''` | `?current=1&size=10&definitionKey=` ← **键在，值是空串** ❌ |

后果分两种，**不一样**：

- `status` 空串 → 后端 `applyStatusFilter()`（`ProcessInstanceServiceImpl.java:146-149`）判的是 `isBlank()`，空串当「不过滤」放过去，**恰好没事**
- `definitionKey` 空串 → 走 `query.processDefinitionKey("")`，**真的按空字符串去匹配，返回 0 条**

所以 `|| undefined` 不是洁癖，是**必需**。这就是 `03` 文档 `:45-46` 那条 ⚠️ 注释、以及自查清单 `:569` 那题的答案。

> ⚠️ **别用 `|| null` 替代**：axios v0 与 v1 对 params 里 `null` 的处理不一致（v0 跳过，v1 某些版本会拼成 `?key=`）。`undefined` 各版本行为一致。**统一用 `undefined`。**

### 场景 4 · 默认参数只认 `undefined`（反直觉）

```js
function f(x = 10) { return x }
f()           // 10
f(undefined)  // 10     ← 触发默认值
f(null)       // null   ← 不触发！null 被当成一个"正经值"
```

`pageInstances(current = 1, size = 10, ...)`（`:47`）的默认值机制就绑在这条规则上。这也是 JS 社区「缺省一律用 undefined 表达」惯例的由来。

---

## 五、动手实验

**实验 1 · 两个空的区别**（浏览器 console，直接粘）：

```js
const a = { x: null }, b = {}
console.log(a.x, b.x)                              // null undefined
console.log('x' in a, 'x' in b)                    // true false      ← 差别在这
console.log(Object.keys(a), Object.keys(b))        // ['x'] []
console.log(JSON.stringify(a), JSON.stringify(b))  // {"x":null} {}   ← 场景 2 的证据
```

**实验 2 · 默认参数的不对称**：

```js
const f = (x = '默认值') => x
console.log(f(undefined), '|', f(null), '|', f(''))
// 默认值 | null | (空串)      ← 三个"空"，三种结果
```

**实验 3 · `||` 与 `??` 的分界**（关系到本项目该用哪个）：

```js
const show = v => `${JSON.stringify(v)} → || : ${JSON.stringify(v || '兜底')} , ?? : ${JSON.stringify(v ?? '兜底')}`
;[undefined, null, '', 0, false, 'ok'].forEach(v => console.log(show(v)))
```

**看点**：`''`、`0`、`false` 三行里，`||` 兜了底而 `??` 没有。
→ `||` 对**所有 falsy 值**生效，`??` 只对 **null / undefined** 生效。
→ 所以 `03` 文档里用 `||` 是**故意且正确**的（就是要把空串一起转掉）；哪天参数换成数字且 `0` 是合法值，`||` 就会变成 bug，那时才该换 `??`。

**实验 4 · axios 真实行为**（在本项目里跑，最有说服力）：
开 Network 面板，把 `definitionKey` 分别传 `'leaveProcess'` / `''` / `undefined`，对比三次的 Request URL。

**"咦？"落在空串那次** —— URL 里真的带着 `&definitionKey=`，而且返回 `total: 0`：明明什么都没选，列表却空了。这个现象如果不知道成因，能查一下午。

---

## 六、常见误解速查表

| 误解 | 实际 |
|---|---|
| `null` 和 `undefined` 差不多，随便用 | 是两件事：格子空 vs 没格子。`in` / `Object.keys` / `JSON.stringify` 都能看出差别 |
| 后端可能返回 `undefined` | ❌ JSON 里没有 undefined，**永远不会**。所以响应类型不该写 `?:` |
| `?:` 和 `\| null` 可以互换 | ❌ 方向不同用途不同，见第一节的表 |
| 写了 `\| null` 就等于做了校验 | ❌ 那只是**人肉抄来的一句承诺**，没有任何东西验证它 |
| `\|\|` 和 `??` 一样 | ❌ `\|\|` 会把 `''`、`0`、`false` 一起兜掉 |
| `typeof null` 是 `'null'` | ❌ 是 `'object'`，1995 年的 bug，永久保留 |
| params 传 `null` 和 `undefined` 效果一样 | ⚠️ 不保证，axios 版本间有差异。统一用 `undefined` |

---

## 七、回到本项目

### ① `| null` 是人肉抄的契约，TS 不验证它

`endTime: string | null` 这个 `| null` **没有任何东西在保证它是对的**。它是作者读了后端 `ProcessInstanceVO.java` 之后手写的一句承诺。后端哪天改了字段可空性，这一行**不会自动变红**。

跟上一篇 [`字面量联合类型与enum.md`](./字面量联合类型与enum.md) 第六节是同一条主线：**TS 的保护到 HTTP 边界为止，边界另一头靠的是后端实现的严谨 + 人工同步的纪律。**

### ② `processDefinitionName: string` 其实不够严谨

Flowable 的 `getProcessDefinitionName()` 在 BPMN 的 `<process>` 标签**没写 `name` 属性**时返回 `null`。严格说 `03:26` 该是 `string | null`。

当前四个模板都写了 name（见 `../../测试进度断点.md` 第二节），所以**现在安全** —— 但**安全来自模板，不来自类型声明**。将来手动部署一个没写 name 的流程，表格那列会显示空白，而 TS 事先一声不吭。

### ③ ⚠️ 哑雷：`suspended` 在 HI 路径恒为 `false`

`ProcessInstanceVO.of(HistoricProcessInstance)`（`ProcessInstanceVO.java:77-90`）**没有 `setSuspended(...)`** —— ACT_HI_PROCINST 里本来也没有「挂起」这个概念。Java 的 `boolean` 是原始类型默认 `false`，于是：

> **凡是走 `myStarted()` / HI 查询回来的实例，`suspended` 永远是 `false`**，不管它实际是不是挂起的。

`03:35` 注释写了「本页不用」，所以**当前无害**。但它是个哑雷：Day 17 待办页、Day 18 历史页若有人顺手读 `row.suspended`，会拿到一个**永远为假的值**，而 TS 完全看不出问题 —— 类型是 `boolean`，值也确实是个合法 boolean。**这正是「类型对了不代表值对了」的现场标本。**

已登记进 `../../测试进度断点.md` 的小尾巴清单。

---

## 八、一句话总结

`string` 是「一定有」，`string | null` 是「格子在、可能空」，`?: string` 是「格子可能不在」；**响应用 `| null`（JSON 里没有 undefined），请求用 `?:`（undefined 的键在 stringify 时整个消失 = 不传这个字段）** —— 方向决定写法，不是口味问题。

---

## 九、往下可以再挖的

1. **`??` 与 `?.` 的完整规则** —— 实验 3 只碰了 `??` 的边。`?.` 的短路行为（`a?.b.c` 里 `.c` 也会一起跳过）比看上去微妙。
2. **`unknown` vs `any`** —— `03:41` 的 `Record<string, unknown>` 为什么不写 `any`。`unknown` 是「我不知道是什么，你用之前必须先收窄」，`any` 是「别管我」。
3. **边界校验（zod / valibot）** —— ① 和 ② 那两个洞的正经修法：在 HTTP 边界做一次运行时校验，让类型与现实重新对齐。**是第三条链前三篇共同的收口**。
4. **`Partial<T>` / `Required<T>`** —— 批量给字段加减 `?:` 的工具类型；表单编辑态（字段可以为空）与提交态（必填）的类型复用会用到，P6 表单设计器要面对。
