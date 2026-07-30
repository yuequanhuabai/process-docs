# async / await 与 JS 单线程（答疑笔记 · 第二版）

> 由答疑 CLI 整理。通用前端原理 · **地基级**。
> 触发点：`handleToggleSuspend` 里，会不会 `await` 那行还没跑完就先执行 `loadList()` 了？追问：**await 是同步线程的意思吗？**
> **第二版说明**：初版只讲了"是什么、为什么不阻塞"。这一版按现在的解析规则重写——补上**诞生背景、设计目的、适用场景**，并且**把 async/await 编译出来，直接看它的真身**（第五~七节）。文中所有时序结论都是**在本机 Node v24.14.1 上实跑验证过的**，不是凭记忆。
> 关联代码：`src/views/process/index.vue:86-99, 102-123`。姊妹篇：`原生控件的外衣与el-switch.md` 第四节（那里讲的是**同步**的顺序保证，和本篇的异步顺序容易混，值得对照）。
> 面向后端背景：全程用 Java 的线程/阻塞概念做对照。

---

## 零、三个结论先行

| 问题 | 答案 |
|---|---|
| 会不会 `await` 没完就先执行 `loadList()`？ | **不会。** await 保证了**函数内部**的先后顺序 |
| 那 await 是"同步/阻塞线程"的意思吗？ | **不是。** 线程一点没停，等待期间它跑别的去了 |
| 那"顺序"到底靠什么保证的？ | **靠把函数劈成一个状态机**——第五节会把编译产物摊开给你看 |

前两句看起来矛盾——"既保证顺序，又没停下来"。**理解这个不矛盾，就是本篇的全部内容。**

---

## 一、先纠正最大的误解

> **`await` 挂起的是「这个函数」，不是「这条线程」。**

后端直觉是这样的（Java）：

```java
processDefinitionService.suspend(definitionId);  // 线程停在这，直到返回
loadList();                                       // 然后才走这行
```

这里"顺序"和"阻塞"是**捆绑**的：因为线程被占住了，所以下一行才走不了。**一件事，一个原因。**

JS 里这两件事被**拆开**了：

```ts
await suspendDefinition(row.id)   // 函数停在这，但线程走了
loadList()                        // 等响应回来，函数才被"唤醒"接着走这行
```

- **顺序**：仍然保证 ✅
- **阻塞**：完全没有 ❌

后端的心智模型里没有"函数停了但线程没停"这种东西——除非你接触过 **Kotlin 的 `suspend`、Go 的 goroutine、或 Java 21 的虚拟线程**，那三个正是同一个思路。卡住很正常。

---

## 二、诞生背景：JS 为什么只有一根线程

这不是"没来得及做多线程"，是**一开始就选定的**。

**1995 年，JS 出生在浏览器里**，任务是给网页加点交互——校验个表单、弹个提示、改改 DOM。

假设它是多线程的，那么两个线程同时改同一个 DOM 节点会怎样？你需要锁、需要处理竞态和死锁。**对一门"让网页动起来"的脚本语言，这个代价太荒唐了**——写个表单校验还得先想清楚同步策略。

于是选了 **单线程 + 事件循环**：一次只干一件事，天然没有数据竞争，DOM 不需要任何锁。

**代价是硬性的**：这根线程还兼职渲染页面、响应点击、跑定时器——**全排在同一根线程上**。所以任何阻塞都会让界面直接冻住。

于是有了那条推论：

> **JS 里所有 IO（网络、文件、定时器）一律是异步的，没有"阻塞版"的 API 可选。**

这不是风格问题，是这门语言的物理约束。Java 有 `InputStream.read()` 这种阻塞式 API，JS **压根没有对应物**。

**验证一下这个约束的真实性**——JS 里真正能阻塞线程的写法长这样，粘进浏览器 console：

```js
const t = Date.now(); while (Date.now() - t < 3000) {}
```

页面会实打实卡死 3 秒：动画停、按钮点不动、滚不了。**这才叫"占着线程"。`await` 从不这么干**——你点「挂起」时页面是活的，这就是反证。

---

## 三、演进史：三代异步写法

异步是被逼的，但异步代码难写。三十年里换了三代。

### 第 1 代 · 回调（1995–2010）

```js
suspendDefinition(id, function (err, res) {
  if (err) return handleError(err)
  loadList(function (err2, list) {
    if (err2) return handleError(err2)
    doSomething(list, function (err3) {        // ← 回调地狱
      ...
    })
  })
})
```

**痛点，四条，每条都致命：**

1. **嵌套无限加深**——三层就已经看不清了；
2. **`try/catch` 完全失效**——回调是在未来的某个时刻、由别人的调用栈发起的，你的 `try` 早就退出了，**根本不在同一个调用栈上**；
3. **错误处理靠约定**——Node 搞了个 `(err, data)` 的一等参数约定，纯靠自觉，漏判一个就静默吞掉；
4. **循环和条件分支写不了**——"依次处理 10 个 id"这种需求，用回调得手写递归。

### 第 2 代 · Promise（2012 起流行，ES6/2015 进标准）

```js
suspendDefinition(id)
  .then(() => loadList())
  .then(list => doSomething(list))
  .catch(err => handleError(err))     // ← 一个 catch 收尾所有环节
```

**解决了什么**：嵌套拉平成链；错误沿链传递、统一 catch；**"未来的值"第一次成为一个可以传递、可以存进变量的一等公民**（这是最关键的一步——`Promise` 对象本身可以当参数传、当返回值返、塞进数组）。

**还剩什么没解决**：链式仍然不是普通控制流。想在中间加个 `if`、想 `for` 循环、想在 catch 之后接着往下走——都得绕。而且**中间变量传递很难受**：第一个 `.then` 里拿到的东西，想在第三个 `.then` 里用，只能层层往下传或者提到外面去。

### 第 3 代 · async / await（ES2017）

```ts
try {
  await suspendDefinition(id)
  const list = await loadList()          // ← 中间变量就是普通变量
  if (list.length === 0) return          // ← 普通 if
  for (const item of list) { ... }       // ← 普通 for
  await doSomething(list)
} catch (err) {
  handleError(err)                       // ← 普通 try/catch，真的能接住了
}
```

**代码的形状回到了顺序式。** 能用 `if`/`for`/`try/catch`/普通局部变量——读起来跟同步代码一模一样。

**代价（真实存在，不是走过场）：**

- **它长得太像同步了**，以至于会误导人——你现在这个问题（"await 是不是阻塞线程"）**就是这个代价本身**。第 1、2 代写法丑归丑，但没人会误以为它们是同步的；
- **容易把本可并发的请求写成串行**——顺手一个个 `await` 下去，三个互不相干的请求硬是排成 3 倍往返（第四节详解）；
- **忘写 `await` 时静默出错**——不报语法错，但 `try/catch` 接不住它、顺序也不再保证（第十节实测）。

> **横向对照 · C# 是源头。** `async/await` 是 C# 5.0（2012）先做出来的，JS 借了过来（连关键字都一样），后来 Python、Rust、Kotlin、Swift 全跟上了。**这是近十五年编程语言层面传播最广的一个设计**。也就是说这套东西不是 JS 特色，学会了到处能用。

---

## 四、设计目的与适用场景

### 设计目的（一句话）

> **让异步代码的「形状」变成顺序的**（好读、好写、能用语言原生的控制流），**同时保留异步的「行为」**（不阻塞线程）。

它换掉的是**写法**，不是异步这个事实。所以它"看起来像同步"是**刻意设计的成果**——你的直觉"这不就是同步吗"说明这个设计成功了；但它终究只是长得像。

### 适用场景速查（这张表是本节的重点）

| 场景 | 怎么写 | 为什么 |
|---|---|---|
| **后一步依赖前一步的结果** | 逐个 `await` | 本来就必须串行。`await 挂起` 再 `await 刷新` 就是这类 |
| **多个请求互不相干** | ⚠️ **`Promise.all`，别逐个 await** | 逐个 await = N 次往返串起来。三个 200ms 的请求：串行 600ms，并发 200ms |
| **循环里发请求，每次独立** | ⚠️ `await Promise.all(arr.map(f))` | `for (const x of arr) await f(x)` 是**串行**的，10 条数据就是 10 次往返。这是 async/await 最常见的性能陷阱 |
| **需要 `try/catch` 接住失败** | **必须 `await`** | 不 await 的 rejection **逃出 try/catch**，第十节有实测 |
| **后面还有代码要等它做完** | **必须 `await`** | 否则那些代码会先跑 |
| **发射后不管**（埋点、日志） | 可以不 await，但**必须 `.catch(() => {})`** | 否则控制台 `Unhandled rejection` |
| **只是想在完成后做一件小事** | `.then()` 也行 | 但一个函数里别 await 和 .then 混用，读的人要来回切换心智模型 |

**判断口诀：问自己"下一行代码需不需要它的结果、或者需不需要它做完"。需要就 `await`，不需要但可能失败就 `.catch`。**

---

## 五、源码逻辑①：把 async/await 编译出来，看它的真身

前面说"引擎把 await 之后的代码打包成回调"。这句话可以**验证**——让 TypeScript 编译到 ES5（那时还没有原生 async/await，编译器必须手工模拟出来）。

> 本项目的 `tsconfig.app.json` 里 `target: "ESNext"`，async/await 是原样保留、交给引擎的。下面是**专门降级编译**出来的，用来看引擎在概念上做了什么。产物由 `tsc --target es5` 真实生成。

**源码：**

```ts
export async function handleToggleSuspend(id: string) {
  try {
    await suspendDefinition(id)
    ElMessage.success('已挂起')
    await loadList()
  } catch {
  }
}
```

**编译产物（真实输出，去掉了辅助函数）：**

```js
function handleToggleSuspend(id) {
    return __awaiter(this, void 0, void 0, function () {
        var _a;
        return __generator(this, function (_b) {
            switch (_b.label) {                          // ←←← 一个状态机！
                case 0:
                    _b.trys.push([0, 3, , 4]);           // 登记 try 块的范围
                    return [4 /*yield*/, suspendDefinition(id)];   // ← await #1：交出控制权
                case 1:
                    _b.sent();                           // ← 被唤醒，取回结果
                    ElMessage.success('已挂起');
                    return [4 /*yield*/, loadList()];    // ← await #2：再交出控制权
                case 2:
                    _b.sent();                           // ← 再被唤醒
                    return [3 /*break*/, 4];
                case 3:                                  // ← catch 块
                    _a = _b.sent();
                    return [3 /*break*/, 4];
                case 4: return [2 /*return*/];           // 函数真正结束
            }
        });
    });
}
```

**这就是答案。** 你的函数体被切成了一个 `switch`：

- **每个 `await` 是一道切口**，切口两边成了两个 `case`；
- `_b.label` 记录"上次执行到哪个 case 了"——这就是**函数的存档点**；
- `return [4, promise]` = "我不干了，把这个 promise 交出去，等它好了再叫我"；
- 被叫醒时，`label` 已经指向下一个 `case`，从那里接着跑。

**为什么 `loadList()` 不可能抢跑，现在是物理事实**：它在 `case 1` 里，而**进入 `case 1` 的唯一途径**是 `case 0` 交出的那个 promise 完成后有人来调用 `next()`。没有别的入口。

> **注意 `4 /*yield*/` 这个注释**——编译器是用**生成器（generator）** 实现的 await。这不是巧合：**`async/await` 在语言设计上就是"生成器 + 自动驱动器"的组合**。生成器提供"函数能在中途暂停并保存现场"的能力，async/await 只是给它配了个自动喂 Promise 的司机。这个司机就是下一节的 `__awaiter`。

---

## 六、源码逻辑②：驱动器 `__awaiter`——"续体"的物理形态

上面的状态机自己不会动，得有人反复调 `next()` 推它。那个人是 `__awaiter`（真实产物，格式化后）：

```js
var __awaiter = function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value));       } catch (e) { reject(e); } }
        function rejected (value) { try { step(generator["throw"](value));   } catch (e) { reject(e); } }
        function step(result) {
            result.done
              ? resolve(result.value)                              // 状态机跑完了 → 兑现外层 Promise
              : adopt(result.value).then(fulfilled, rejected);     // ←←← 整个 await 的核心就是这一行
        }
        step((generator = generator.apply(thisArg, _arguments || [])).next());   // 踢第一脚
    });
};
```

**盯着 `step` 这一行看：**

```js
adopt(result.value).then(fulfilled, rejected)
```

`result.value` 就是你 `await` 的那个 Promise；`fulfilled` 里面是 `generator.next(value)`——**把状态机推进到下一个 `case`**。

翻译成人话：

> **`await` = 把"函数剩下的部分"注册成这个 Promise 的 `.then` 回调。**

初版里说的"续体"，物理形态就是这个 `fulfilled` 函数。它一被登记上去，`__awaiter` 就返回了，**调用栈彻底清空，线程自由**。

**四个结论顺带全出来了：**

1. **async 函数为什么总是返回 Promise** → 因为 `__awaiter` 第一行就 `return new Promise(...)`，函数体还没开始跑呢；
2. **`await` 非 Promise 值为什么也要等一下** → `adopt()` 会把它包成 Promise，包完还是要走 `.then`，**照样得排一次队**（第八节有实测）；
3. **rejection 怎么变成异常的** → `rejected` 里调的是 `generator["throw"](value)`，**把 rejection 当异常扔回状态机内部**——所以你的 `catch` 块才能接住；
4. **`await` 是纯粹的语法糖，一行引擎特权都没用** → 上面这段就是普通 JS，`Promise` + 生成器就够了。

---

## 七、源码逻辑③：`try/catch` 凭什么能跨越 await

第三节说过，回调时代 `try/catch` 是失效的——因为回调不在同一个调用栈上。**async/await 的 `try/catch` 也是跨调用栈的，凭什么它就有效？**

看编译产物里那两行不起眼的代码：

```js
case 0:
    _b.trys.push([0, 3, , 4]);   // ← "case 0 到 case 3 之间出错，跳到 case 3；收尾在 case 4"
    ...
case 3:
    _a = _b.sent();              // ← catch 块的内容
```

**`try/catch` 被编译成了一张跳转表，存在状态机的 `trys` 数组里。**

于是恢复执行时，是这样的：`rejected(err)` → `generator.throw(err)` → 状态机内部查 `trys` 表 → 发现当前 `label` 落在 `[0, 3]` 区间 → 把 `label` 改成 `3` → 跳进 catch 块。

**关键点：`trys` 这张表和 `label` 一样，是存在状态机对象里的**，不依赖调用栈。所以哪怕真正的 rejection 发生在 500 毫秒后、由一个完全不相干的网络回调触发，这张表还在，`catch` 照样生效。

> **这也一次讲清了为什么"没 await 的 promise 逃得出 try/catch"**：
> 没有 `await`，`suspendDefinition(id)` 就不会被编译成 `return [4, ...]`——它只是一句普通的同步调用语句，**同步部分立刻成功返回了一个 pending Promise**，状态机压根没在这里暂停。那个 Promise 后来 reject，**跟这张 `trys` 表已经毫无关系了**。
> 第十节有实测输出。

---

## 八、引擎层：微任务队列与实测时序

前七节讲的是"函数怎么被切开"。还剩一个问题：**续体被唤醒后，排在谁前面？**

答案是**微任务队列**（microtask queue）。事件循环每跑完一段同步代码，就把微任务队列**整个抽干**，然后才去拿下一个宏任务（`setTimeout`、DOM 事件、网络回调）。

**实测**（本机 Node v24.14.1，输出是真实的）：

```js
console.log('1 script start')
setTimeout(() => console.log('7 setTimeout'), 0)
async function async2() { console.log('2 async2 body') }
async function async1() { await async2(); console.log('5 async1 after await') }
async1()
new Promise(r => { console.log('3 promise executor'); r() }).then(() => console.log('6 then'))
console.log('4 script end')
```

```
1 script start
2 async2 body          ← async 函数体的同步部分是【立刻执行】的，不是排队
3 promise executor     ← new Promise 的执行器也是同步的
4 script end
5 async1 after await   ← 微任务：await 的续体
6 then                 ← 微任务：后登记的排在后面
7 setTimeout           ← 宏任务：所有微任务清空后才轮到
```

**三个要点：**

1. **调用一个 async 函数，它的同步部分立刻就跑**（`2` 排在 `4` 前面）。"async 函数是异步的"这话不准确——**它只在遇到第一个 `await` 时才变异步**；
2. **续体走的是微任务，一定跑在 `setTimeout` 前面**（`5` 早于 `7`）——哪怕 setTimeout 写的是 0ms；
3. **微任务之间按登记先后排队**（`5` 早于 `6`，因为 `async1()` 那行在 `new Promise` 那行前面）。

> **一段历史**：`await` 曾经比手写 `.then()` 多绕好几个微任务 tick，同样的代码在老引擎上 `5` 会排到 `6` 后面。V8 7.2（Chrome 73 / Node 12，2019 年）的 **"await 优化"** 把这个开销抹平了。所以**网上 2019 年之前的文章讲这个例子，结论和你今天跑出来的不一样**——遇到对不上的，以自己跑的为准。

---

## 九、动手实验（浏览器 console 直接粘）

看字容易滑过去，跑一遍最快。F12 → Console。

**实验 1 · 顺序保证 ✅ 与非阻塞 ✅ 同时成立**

```js
async function demo() {
  console.log('1 进入函数')
  await new Promise(r => setTimeout(r, 2000))
  console.log('3 await 之后')
}
demo()
console.log('2 函数外面')
```

输出 `1` → `2` →（等 2 秒）→ `3`。看两件事：`3` 在 `1` 之后（**函数内顺序保证**）；`2` 插进了 `1` 和 `3` 中间（**函数没走完，线程已经跑去干别的了**）。

**实验 2 · 等待期间线程是活的**

```js
let n = 0
const timer = setInterval(() => console.log('心跳', ++n), 300)
;(async () => {
  console.log('开始等待')
  await new Promise(r => setTimeout(r, 2000))
  console.log('等待结束'); clearInterval(timer)
})()
```

2 秒里"心跳"每 300ms 照打 → **线程完全没被占住**。

**实验 3 · 对照组：真正的阻塞长什么样**

```js
let n = 0
const timer = setInterval(() => console.log('心跳', ++n), 300)
console.log('开始阻塞')
const t = Date.now(); while (Date.now() - t < 2000) {}
console.log('阻塞结束'); clearInterval(timer)
```

这 2 秒**一条心跳都不打**（全堵在队列里，结束后一股脑补上），页面卡死点不动。**实验 2 vs 实验 3 就是 await 和阻塞的区别**——同样等 2 秒，一个线程自由、一个线程死掉。

**实验 4 · `await` 一个普通值也会让出一次**

```js
async function f() { console.log('2 await 前'); await 42; console.log('4 await 42 之后') }
console.log('1 开始'); f()
Promise.resolve().then(() => console.log('3 一个微任务'))
console.log('X 同步末尾')
```

实测输出：`1` → `2` → `X` → `4` → `3`。`4` 在 `X` 后面 → **`await 42` 确实让出了一次**（第六节的 `adopt()` 包装）；`4` 在 `3` 前面 → **只让出了一次**（2019 年的 await 优化）。

**实验 5 · 亲手把 await 编译出来看**（想彻底破除"魔法感"就做这个）
打开 [TypeScript Playground](https://www.typescriptlang.org/play)，右侧 TS Config 把 **Target 改成 ES5**，左边粘一个 async 函数 → 右边直接出现第五节那个 `switch (_b.label)` 状态机。改改代码看 `case` 怎么跟着变，特别是加一个 `for` 循环进去。

---

## 十、回到本项目：`loadList()` 的四处调用

**先说结论：你最初担心的"顺序抢跑"不存在，但这里确实有个真问题，位置提前了一个身位。**

`views/process/index.vue` 里 `loadList()` 被调用四次，**没有一次带 `await`**：

| 位置 | 所在函数 | 是 async 吗 | 能直接 await 吗 |
|---|---|---|---|
| `:95` | `handleToggleSuspend` | ✅ | 能 |
| `:119` | `handleDelete` | ✅ | 能 |
| `:127` | `handlePageChange` | ❌ | 不能（得先改成 async） |
| `:133` | `handleLatestChange` | ❌ | 不能（同上） |

而 `loadList` 内部（`:74-83`）**只有 `try/finally`，没有 `catch`**——请求失败时它会返回一个 rejected Promise。

### 后果一：rejection 逃出了 try/catch（实测）

```js
function boom() { return Promise.reject(new Error('列表刷新失败')) }
async function noAwait()   { try { boom()       } catch { console.log('接住了') } }
async function withAwait() { try { await boom() } catch (e) { console.log('接住了 ->', e.message) } }
```

实测输出：

```
A 没 await：try 里啥事没有
  >> UNHANDLED REJECTION: 列表刷新失败      ← 逃了
B 有 await：catch 接住了 -> 列表刷新失败      ← 接住了
```

原理见第七节：**没有 `await`，这行就没被编译成状态机的暂停点，跟 `trys` 跳转表毫无关系。**

功能上不致命（`request.ts` 拦截器已经弹过错了），但控制台会有红色的 unhandled rejection，是漏网。

### 后果二：顺序保证只在"后面没代码"时才成立

现在 `loadList()` 恰好都是各函数的最后一行，看不出毛病。**但一旦以后往下加东西**——关弹窗、清空选中行、重置某个状态——**那些代码会先于列表刷新完成执行**。你最初担心的那类问题，真实入口就在这。

### 怎么改：两个方案，推荐后者

**方案 A · 每个调用点加 `await`**——两处能直接加，另两处得先把 handler 改成 `async`。四处都要动。

**方案 B（推荐）· 在 `loadList` 内部补 `catch`**，让它**永不 reject**：

```ts
async function loadList() {
  loading.value = true
  try {
    const page = await pageDefinitions(current.value, size.value, latestOnly.value)
    list.value = page.records
    total.value = page.total
  } catch {
    // 错误提示已由 request.ts 拦截器统一处理，这里只负责别让 rejection 逃出去
  } finally {
    loading.value = false
  }
}
```

**改一处，四个调用点同时安全**，而且和现有的"错误统一由拦截器处理"的约定一致。如果哪天需要"刷新完再做点什么"，那时再在具体调用点加 `await` 也不迟——**方案 B 不妨碍以后加方案 A**。

### 后果三：并发竞态（`await` 治不了）

连点两次操作会有并发的 `loadList()` 在途，响应回来的顺序不保证，旧数据可能覆盖新数据。

**这条 `await` 解决不了**——它管的是单个函数内部的顺序，管不了两次独立的点击。解法是**在请求期间禁用控件**，`loading` ref 现成的：给开关加 `:loading="loading"`（详见 `原生控件的外衣与el-switch.md` 第八节）、给分页器和操作按钮加 `:disabled="loading"`。

> **顺带看一眼这个竞态是怎么自证 await 非阻塞的**：如果 `await` 真阻塞线程，第一次点击没返回之前线程被占死，**你的第二次点击根本没机会被处理**，压根不会产生并发。**竞态能发生 ⟺ 等待期间线程是自由的。**

---

## 十一、常见误解速查

| 误解 | 实际 |
|---|---|
| await = 线程停在这儿 | ❌ 只有**函数**停了（存档成状态机），线程该干嘛干嘛 |
| await 会让页面卡住 | ❌ 恰恰相反，它就是为了**不卡**才存在的 |
| async 函数会开新线程 / 并行 | ❌ JS 单线程，从头到尾一根。要真并行得用 Web Worker |
| 加了 `async`，函数就整个变异步了 | ❌ **同步部分立刻执行**（第八节实测 `2` 排在 `4` 前）。它只在遇到**第一个 await** 时才变异步 |
| await 后面必须是 Promise | ❌ 任何值都行，但 `adopt()` 会包一层，**照样让出一次**（实验 4） |
| await 的顺序保证是全局的 | ❌ 只保证**当前函数内部**。函数外面、别的函数随时插进来（实验 1 的 `2`） |
| 不写 await 只是拿不到返回值 | ❌ 还有两个后果：**rejection 逃出 try/catch**、**后续代码抢跑**（第十节实测） |
| 一串 await 写下来是"并发发请求" | ❌ 是**串行**。三个独立请求各 200ms，逐个 await 要 600ms；`Promise.all` 只要 200ms |
| `await` 比 `.then()` 慢 | ❌ 2019 年 V8 优化后**开销一样**。老文章的结论已经过时（第八节） |
| async/await 是 JS 独有的 | ❌ C# 2012 年首创，JS 借来的，Python/Rust/Kotlin/Swift 全跟进了。**学一次到处用** |

---

## 十二、一句话总结

> **`await` 挂起的是「函数」，不是「线程」。** 编译产物摊开看就是：函数被切成一个 `switch` 状态机，每个 `await` 是一道切口，`return [4, promise]` 交出控制权，`promise.then(推进状态机)` 负责把它叫醒。函数当场退出、线程继续干别的；等 Promise 完成，下一个 `case` 才开始跑。
> 所以它**同时**做到了：函数内部顺序有保证（`loadList()` 不会抢跑）＋ 线程不被阻塞（页面不卡、第二次点击照样被处理）。
> 它存在的根本原因：**JS 只有一根线程且身兼渲染，阻塞 = 界面死给用户看**，所以所有 IO 必须异步；而异步代码难写，于是三十年里从回调链演进到"形状是同步的、行为是异步的"这个折中。
> **代价就是它太像同步了**——你最初那个疑问，正是这个设计付出的代价本身。

---

## 十三、往下可以再挖的

- **`Promise.all` / `allSettled` / `race`**：并发的正确姿势。`all` 一个失败就整体失败，`allSettled` 全等完再看结果。**P4 后面的页面要同时拉「待办数 + 已办数 + 流程列表」时立刻用得上**，别写成三个串行 await。
- **循环里的 await**：`for (const x of arr) await f(x)` 是串行；独立任务应写 `await Promise.all(arr.map(f))`。这是最常见的性能陷阱，值得单独成篇。
- **事件循环的完整图景**：宏任务 / 微任务 / 渲染时机（`requestAnimationFrame` 插在哪）。第八节只用到了"微任务优先"这一层。
- **请求竞态的正规解法**：给请求编号只认最后一次，或用 `AbortController` 取消在途请求。比"禁用按钮"更彻底，表格页搜索框防抖时几乎必用。
- **生成器（generator）本身**：`function*` / `yield`。第五节看到 async/await 就是它 + 自动驱动器，反过来学一遍生成器，这套机制会彻底透明。
- **Vue 的 `nextTick` 也是微任务**——`原生控件的外衣与el-switch.md` 第四节讲的"变量同步更新、DOM 异步更新"，那个"异步"就是本篇的微任务队列。**两篇在这里接上了。**
