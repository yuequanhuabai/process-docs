# Teleport 与弹窗的渲染位置

> **触发点**（2026-08-11，写 `views/myStart/index.vue` 的发起弹窗时）：
> ① 「现在的代码启动，为什么我点击『发起流程』，页面没有弹窗响应？」
> ② 「我在 `03-完整代码.md` 的发起流程位置找不到弹窗组件，却在**分页组件后面**找到了 —— 弹窗一般都写在最后吗？」
> ③ 「现在出现了弹窗组件，页面的布局有什么影响吗？」
>
> ⚠️ **本篇的源码结论全部基于 `element-plus@2.14.2`**（本项目 `package.json` 锁定的版本）。Element Plus 改过好几次弹窗实现，**换版本必须重查**，查法见第九节。

---

## 零、先记住这五条（其余都是为了解释它们）

看不懂下面的推导没关系，先把这五条记住，够你写完弹窗：

| # | 结论 |
|---|---|
| 1 | **点按钮没反应，是因为模板里根本没有 `<el-dialog>`。** `dialogVisible` 从 `false` 变成 `true` 了，但没有任何人在读它 —— Vue 不会为一个没人关心的变量做任何事 |
| 2 | **弹窗写在模板最后，是可读性惯例，不是技术要求。** 写在按钮旁边也能弹，只是没人这么写 |
| 3 | **弹窗对你的布局零影响**，三道保险各自独立：没打开过就没 DOM ／ 关闭时 `display:none` ／ 打开时 `position:fixed` 脱离文档流 |
| 4 | ⚠️ **"el-dialog 用 Teleport 把 DOM 搬到 body" 这个说法，对我们这个版本是错的** —— 默认**不搬**。结论碰巧对，理由全错 |
| 5 | **给弹窗写样式要用 `:deep(.el-dialog__body)`，且不要带 `.my-start` 之类的祖先前缀** —— 前缀在将来加了 `append-to-body` 时会静默失效 |

**核心那句话**，值得单独记：

> ### 写在哪 ≠ 渲染在哪 ≠ 占不占位
>
> 这是**三件独立的事**，由三个不同的开关控制：**模板里的位置** / `appendToBody` / `position`。
> 三者混为一谈，是所有弹窗类问题的根源。

---

## 一、先纠三个误解

**误解 1：「改了 ref，界面就会变。」**

反的。Vue 的响应式是**"拉"不是"推"** —— 模板读过谁，谁才有资格触发更新。见第二节。

**误解 2：「组件写在哪，就渲染在哪，就在哪占位置。」**

三件事在弹窗这里全部脱钩。见第三、四节。

**误解 3（这条最值钱）：「el-dialog 内部用了 Teleport，DOM 会被搬到 `<body>` 底下。」**

这是网上流传最广的答案，**对 `element-plus@2.14.2` 是错的：默认不搬。** 见第三节的源码。

> 📌 **为什么要专门纠这条**：它的**结论**（不影响布局）碰巧是对的，所以没人会发现它错。但**理由**错了，往下推第二题就会翻车 —— 比如第八节那个 `:deep()` 该不该带祖先前缀的问题。
> 这就是《讲解规则》第五节那条规矩的由来：**训练数据给的高概率答案，只配当草稿。**

---

## 二、第一层：点了按钮为什么没反应

### 2.1 现场

当时 `myStart/index.vue` 的状态是：

```js
const dialogVisibal = ref(false)      // 拼写笔误，应为 dialogVisible

function openDialog() {
  form.processDefinitionKey = ''
  form.businessKey = ''
  form.reason = ''
  formRef.value?.clearValidate()
  dialogVisibal.value = true          // ← 这行确实执行了
}
```

模板里有按钮 `<el-button @click="openDialog">发起流程</el-button>`，**但从头到尾没有 `<el-dialog>`，也没有任何一处出现 `dialogVisibal`。**

点击是**成功的**：三个字段清空了，`dialogVisibal.value` 也确实变成了 `true`。变量层面一切正常。

### 2.2 为什么"变量对了"却"界面没动"

Vue 的响应式，很多人的直觉是：

> 「我改了 ref → Vue 收到通知 → 界面更新」（**推**模型）

真实机制是反的：

> 「渲染时读到了谁 → 把这个依赖登记下来 → 以后谁被改了，去查**谁登记过它** → 查到就更新，**查不到就什么也不做**」（**拉**模型）

分三步：

1. **依赖收集**：组件首次渲染时，模板里每读一个 ref，Vue 就在那个 ref 的"订阅者名单"上记一笔
2. **触发**：某个 ref 被赋新值，Vue 翻开它的名单
3. **更新**：名单上有人 → 通知他们重渲染；**名单是空的 → 直接返回，零成本**

`dialogVisibal` 的名单从来没人签过名。所以它 `true` 也好 `false` 也好，Vue 无事可做。

**它不是"没生效"，是压根没有可生效的对象。**

### 2.3 后端类比

这就是**观察者模式**，但订阅关系不是你手写 `addListener()` 注册的，而是**"谁读过我"自动登记**的。

对应到 Java：你有个 `EventBus`，`publish(event)` 时去查 `subscribers` 这个 Map。你现在的情况是 —— **`subscribers` 里那个 key 对应的 List 是空的**。`publish` 照常执行、不报错、不抛异常，只是循环体一次都没进去。

**这类 bug 的共性：变量写对了 ≠ 界面接上了。** 中间必须有一根线，把 JS 里的状态接到 DOM 上。弹窗这根线就是 `v-model`。

### 2.4 顺带：为什么 build 会红

```
src/views/myStart/index.vue(95,7): error TS6133: 'submitting' is declared but its value is never read.
```

**同一个病根**：声明了状态，没人消费。TS 的 `noUnusedLocals` 在编译期就把这类"半截活"揪出来了 —— 这次它比浏览器更早发现问题。

> 💡 **值得记的一点**：`dialogVisibal` 没被 TS 报出来，因为 `openDialog()` 里写了它（算"被读过"）；`submitting` 一次都没写过，所以中招。**TS 能查出"完全没用过"，查不出"用了一半"。** 前者是编译错误，后者只能靠自己发现。

---

## 三、第二层：写在哪 ≠ 渲染在哪

### 3.1 惯例确实存在

弹窗写在模板最后，是通行写法。本项目就有两个样本：

| 文件 | 结构 |
|---|---|
| `src/views/user/index.vue`（Day 8–9，CLI 生成） | `el-table`(`:166`) → `el-pagination`(`:188`) → `el-dialog`(`:197`) |
| `process_instance/03-完整代码.md` 第 3 节（myStart 范本） | 同上，`el-dialog` 在 `:466` |

### 3.2 但流行的解释是错的

**流行说法**：「`el-dialog` 内部用了 Teleport，DOM 会被搬到 `<body>` 底下，所以写哪都一样。」

翻 `element-plus@2.14.2` 的编译产物：

```js
// node_modules/element-plus/es/components/dialog/src/dialog.mjs
:14    appendToBody: Boolean,        // ← 裸 Boolean，不在下面的 defaults 块里 ⇒ 默认 false
:136   appendTo: "body",             // ← 这个才有默认值

// node_modules/element-plus/es/components/dialog/src/dialog.vue_vue_type_script_setup_true_lang.mjs
:58-60
createBlock(Teleport, {
  to: __props.appendTo,
  disabled: __props.appendTo !== "body" ? false : !__props.appendToBody
})
```

代入默认值算一遍：

```
appendTo === "body"           → 三元的条件 (appendTo !== "body") 为 false
                              → 走 false 分支 → disabled: !appendToBody
appendToBody === false        → disabled: !false
                              → disabled: true   ← Teleport 被关掉了
```

**结论：你不主动写 `append-to-body`，弹窗的 DOM 就老老实实待在你写它的位置** —— 也就是 `.pager` 那个 div 后面，`.my-start` 的第 4 个子节点。

> `<Teleport disabled>` 是 Vue 3 的正经用法：**传送门造好了但不启用，内容留在原地**。Element Plus 用它把"要不要搬家"做成一个可切换的开关，而默认值是**不搬**。

### 3.3 那真正的理由是什么

三条，**全是给人看的，跟浏览器无关**：

| # | 理由 | 展开 |
|---|---|---|
| 1 | **常态是"不存在"** | 99% 的时间弹窗关着。把一个平时压根不显示的东西插在按钮和表格中间，会拦腰打断读主流程的视线 |
| 2 | **篇幅压制** | 一个 dialog 连 `el-form` + 若干 `form-item` + footer 通常 20–40 行。塞进 `.toolbar` 会把那十行工具条彻底淹掉，「扫一眼 div 就看清宏观布局」（你在实例页定的规矩）当场作废 |
| 3 | **常常不止一个** | "新增 / 编辑 / 详情"三个弹窗一页很普遍。统一堆末尾，找起来有固定去处 |

**一句话：写在最后是可读性惯例，不是技术约束。**

---

## 四、第三层：渲染在哪 ≠ 占不占位

弹窗的 DOM 确实就在 `.my-start` 里面（因为 Teleport 关着），**但它对布局零影响**。三道保险各自独立，坏一道还有两道。

### 4.1 保险一 · 懒渲染：没打开过就没 DOM

```js
// node_modules/element-plus/es/components/dialog/src/use-dialog.mjs
:24    const rendered = ref(false);          // ← 初始 false
:149   rendered.value = true;                // watch(modelValue) 里，首次打开时置 true
:171   rendered.value = true;                // onMounted 里，若初始就是打开的
:86    if (props.destroyOnClose) rendered.value = false;   // 关闭时是否销毁，destroyOnClose 默认 false
```

渲染函数里对应：

```js
unref(rendered) ? (openBlock(), createBlock(dialog_content_default, ...)) : ...
```

**你还没点过按钮之前，弹窗正文连 vnode 都没生成**，那个位置是一个空注释节点 `<!---->`。

> 顺带：`destroyOnClose` 默认 `false`（`dialog.mjs:29` 是裸 `Boolean`，不在 defaults 块里）。意思是**关闭后 DOM 会留着**，下次打开更快、表单内容也还在。所以 `openDialog()` 里那三行手动清空字段**是必要的**，不是多余 —— 这解释了你已经写对的那段代码为什么必须存在。

### 4.2 保险二 · `v-show`：关闭时 `display: none`

```js
// dialog.vue_vue_type_script_setup_true_lang.mjs
:153   ]), [[vShow, unref(visible)]])
```

外层 `ElOverlay` 挂着 `v-show`。`display: none` 的元素**不参与布局**，不占任何位置。

> **`v-if` 和 `v-show` 的区别正好在这里同时出现**：`rendered` 那层是 `v-if` 的效果（不存在），`visible` 这层是 `v-show`（存在但不显示）。弹窗两层都用了 —— 第一次打开前用 `v-if` 省开销，之后用 `v-show` 换开关速度。

### 4.3 保险三 · `position: fixed`：脱离文档流 ★ 关键

这道是最关键的，也是最需要前端基础的一条。

**先解释"文档流"**：浏览器默认的排版是一条**自动流水线** —— 元素按书写顺序一个接一个排下去，前面的占了多高，后面的就被往下推多少，父容器的高度由子元素撑出来。这就是文档流。

`position: fixed` 的元素**从这条流水线上被拿下来了**：

- 它的定位参照系变成**视口**（浏览器窗口），不再是父元素
- 父容器计算自己高度、计算 flex 子项怎么分配时，**当它不存在**
- 它浮在页面上方独立的一层

弹窗正文外面包着的 `ElOverlay`，两种情况都是 fixed：

```css
/* node_modules/element-plus/dist/index.css */
.el-overlay { z-index:2000; height:100%; position:fixed; top:0; bottom:0; left:0; right:0; overflow:auto }
```

```js
// node_modules/element-plus/es/components/overlay/src/overlay.mjs:31-53
// mask 为 true（默认）→ 渲染 <div class="el-overlay">，吃上面那段 CSS
// mask 为 false        → 渲染的 div 带内联 style: { position:"fixed", top:0, right:0, bottom:0, left:0 }
```

**两个分支都是 `position: fixed`。** 也就是说即使你写 `:modal="false"` 去掉遮罩（`modal` 默认 `true`，`dialog.mjs:140`），它依然不进你的布局账本。

**所以：即便弹窗正开着，`.my-start` 也不会变高，工具条 / 表格 / 分页三条带的位置纹丝不动。**

### 4.4 后端类比

文档流像一个 **LayoutManager 按顺序排列组件**，每个组件占一格，后面的被前面的推着走。

`position: fixed` 相当于**把这个组件从 LayoutManager 里摘出去，改成一个悬浮在窗口上的 overlay 层** —— LayoutManager 重新布局时，它根本不在待排列的集合里。

`z-index: 2000` 就是这个悬浮层的**层级序号**，数字大的盖在上面。

---

## 五、诞生背景：为什么会有 Teleport 这种东西

> 既然默认不搬，那 Element Plus 为什么还要费劲留这个开关？—— 因为有些坑，不搬家就绕不过去。

### 5.1 旧世界：弹窗写在哪，DOM 就在哪

jQuery 和 Vue 2 早期，弹窗就是页面里一个普通的 `<div>`，藏在触发它的按钮旁边，靠 `display` 开关。

### 5.2 痛点：三个 CSS 陷阱，会把弹窗关在笼子里

弹窗有个特殊需求 —— **它必须能盖住整个页面**。而 CSS 里有三种祖先，会把子元素**困死在自己的边界内**：

| # | 祖先身上有 | 后果 |
|---|---|---|
| 1 | `overflow: hidden` | 超出祖先边框的部分**被裁掉**。弹窗可能只露出半截 |
| 2 | 自身形成了**层叠上下文**（有 `z-index` + `position`、`opacity < 1`、`transform` 等） | 子元素的 `z-index` 再大也**翻不出祖先所在的那一层**。写 `z-index: 99999` 依然被别的元素盖住 |
| 3 | `transform` / `filter` / `will-change` | 这个祖先会成为 `fixed` 元素的**包含块** —— 连 `position: fixed` 都被降级成"相对这个祖先定位"，不再相对视口 |

第 3 条最阴 —— 它让你上一节刚学的"fixed 脱离文档流"**失效**。而 `transform` 极其常见（任何一个 CSS 动画、任何一个 `translate` 居中）。

**这三条的共同点：问题出在祖先身上，你在弹窗自己身上改任何 CSS 都救不了。** 唯一的出路是——**离开这个祖先**。

### 5.3 旧方案：手动搬 DOM

Vue 2 时代的 Element UI 就是这么干的：`append-to-body` 属性，内部 `document.body.appendChild(this.$el)`，硬把节点搬到 `<body>` 底下。

**代价**：绕过了框架自己动 DOM，组件卸载时要手动清理（漏了就内存泄漏），而且组件树和 DOM 树彻底脱节 —— 事件冒泡路径、依赖注入的链路全乱了。

### 5.4 新方案：把"搬家"变成框架的一等公民

React 16（2017）先做出 `ReactDOM.createPortal`，关键设计是：

> **DOM 搬走，但组件树关系保持不变。** 依赖注入、事件冒泡仍然按你写代码的位置走，只有真实 DOM 的落点变了。

Vue 3 跟进做成内置组件 `<Teleport>`，多给了一个 `disabled` 开关（可以运行时切换搬不搬）。

> 📌 RFC 阶段它叫 `<Portal>`，后来改名 Teleport，据说是为了避开当时 HTML 标准里一个 `<portal>` 元素提案的命名冲突。**这条属历史掌故，没在源码里查证过。**

### 5.5 代价

| 换来的 | 付出的 |
|---|---|
| 弹窗不再被祖先的 CSS 困住 | **DOM 位置和代码位置对不上**，调试时得去 body 底下找 |
| 组件树关系不变，写法自然 | **scoped 样式里的祖先选择器会失效**（见第八节 —— 这就是那条错理由会把人带沟里的地方） |

### 5.6 那 Element Plus 为什么默认关掉？

源码只告诉我们"默认是关的"，没写为什么。**以下是推测，不是查证结论**：默认不搬，DOM 结构可预测、scoped 样式好写、调试省事；真撞上 5.2 那三个陷阱时，再手动加 `append-to-body` 逃生。**属于"默认简单，需要时才复杂"的取舍。**

---

## 六、动手实验（两分钟，验完删干净）

前提：`views/myStart/index.vue` 的 `<el-dialog>` 已经写好。

**实验 0 · 证明"没人读的 ref 不会让界面动"**（对应第二节）

在模板任意位置临时插一行，然后点"发起流程"：

```vue
<p>dialogVisible 现在是：{{ dialogVisible }}</p>
```

会看到它当场从 `false` 翻成 `true`。这同时证明两件事：① 按钮和 `openDialog()` 本来就没问题；② **模板里一旦出现对它的读取，响应式立刻就通了**。这个 `<p>` 就是最简陋版的"消费者"，`<el-dialog>` 只是体面得多的那个。

**实验 1 · 懒渲染**（对应 4.1）

先别点按钮。F12 → Elements，找到 `.my-start` 的最后一个子节点：是 `div.el-overlay`，Computed 面板里 `display: none`。**展开它往里钻**，弹窗正文的位置是个空注释 `<!---->`。

**实验 2 · 证明没有 Teleport**（对应第三节 ★ 本篇最重要的一步）

点开弹窗，再看 Elements —— 弹窗的 DOM 变成真节点了，而且**它仍然在 `.my-start` 里面**。

**这一眼就推翻了流行说法。**

**实验 3 · 脱离文档流**（对应 4.3）

选中 `.el-overlay`，Computed 面板确认 `position: fixed`。同时量一下 `.my-start` 的高度（Elements 里悬停会显示尺寸），**和弹窗打开前一模一样**。

**实验 4 · 反向验证 Teleport 确实存在，只是关着**

给 `<el-dialog>` 临时加一个 `append-to-body`，重复实验 2 —— **这次它跑到 `<body>` 底下去了**，不再是 `.my-start` 的后代。

> ⚠️ **验完记得删掉这个属性。** 实验 2 和实验 4 的对比，就是本篇的全部核心：**同一份代码、同一个位置，DOM 落点却能变** —— 这就是"写在哪 ≠ 渲染在哪"。

---

## 七、常见误解速查表

| 说法 | 对不对 | 实情（`element-plus@2.14.2`） |
|---|---|---|
| 「el-dialog 会 Teleport 到 body」 | ❌ | 默认 `disabled: true`，**不搬**。`dialog.mjs:14` + `dialog.vue_...mjs:58-60` |
| 「弹窗必须写在模板最后」 | ❌ | 惯例而已，写哪都能弹 |
| 「弹窗会把页面撑高」 | ❌ | 三道保险，零影响 |
| 「关掉遮罩 `:modal="false"` 就会占位了」 | ❌ | 两个分支都是 `position:fixed`，`overlay.mjs:31-53` |
| 「改了 ref 界面就会更新」 | ❌ | 得有人读它。没人读 = 订阅名单为空 = 空转 |
| 「关闭弹窗后表单会自动清空」 | ❌ | `destroyOnClose` 默认 false，DOM 和数据都留着。**必须手动清**（你 `openDialog()` 里那三行） |
| 「`z-index` 写大一点就能盖住一切」 | ❌ | 翻不出祖先的层叠上下文。见 5.2 第 2 条 |
| 「`position:fixed` 一定相对视口」 | ❌ | 祖先有 `transform`/`filter`/`will-change` 时会被降级。见 5.2 第 3 条 |
| 「scoped 样式能改到弹窗内部」 | ❌ | 得用 `:deep()`。见第八节 |

---

## 八、回到本项目

### 8.1 当时的 bug（已定位）

`src/views/myStart/index.vue`，提交 `0d83a61「弹窗」`：加了发起按钮（`:15`）、`openDialog()`（`:115-121`）、表单四件套（`:93-100`），**但 `<el-dialog>` 模板一行没写**，`startInstance` 也没 import。所以点按钮无反应。`npm run build` 同时红在 `submitting` 未使用（TS6133）。

### 8.2 ⚠️ 给弹窗写样式：别带祖先前缀

本页的样式块是 `<style lang="scss" scoped>`，嵌在 `.my-start` 里。等你要调弹窗内部（比如 `.el-dialog__body` 的内边距）会发现**选不中**。

**两个原因叠加**：

1. `scoped` 的原理是给**本组件模板里的元素**打 `data-v-xxx` 属性，再把选择器改写成 `.xxx[data-v-xxx]`。而 `.el-dialog__body` 是 **el-dialog 组件内部**渲染的元素，身上没有你的 `data-v`，匹配不上
2. 所以要用 `:deep()` 穿透

**正确写法**：

```scss
:deep(.el-dialog__body) { padding: 16px 20px; }
```

**错误写法**（现在能用，将来静默失效）：

```scss
.my-start :deep(.el-dialog__body) { ... }   // ⚠️ 别这么写
```

**为什么**：现在 Teleport 关着，弹窗确实是 `.my-start` 的后代，带前缀能匹配上。**但哪天你为了绕开 5.2 那三个 CSS 陷阱加了 `append-to-body`，DOM 搬去 body，这个选择器会当场静默失效** —— 不报错、不警告，样式就是不生效。

> 📌 **这正是《讲解规则》§7.3 ③ 那条警戒线的又一个实例**：评估方案不问"会不会出错"，问"**出错时我会不会知道**"。这里的答案是不会。所以现在就把习惯定死：**给弹窗写样式，顶格写 `:deep(...)`，不带任何祖先前缀。**

### 8.3 顺带

- `dialogVisibal` 拼写应为 `dialogVisible`（visible，-ible 结尾）。不影响运行，但这个名字要在模板、取消按钮、提交函数里各写一遍，**趁只有两处赶紧改**
- 本页 `.muted`（`:55` 用了）和 `.pager`（`:63` 用了）在 `<style>` 里都没定义 —— 同样是**静默失败**，class 是死的，不报错。属 ③ 样式步的待办

---

## 九、一句话总结

> **写在哪 ≠ 渲染在哪 ≠ 占不占位** —— 三件事由三个独立开关控制（模板位置 / `appendToBody` / `position`）。
> 搞清这三层，`el-drawer`、`el-popover`、`el-tooltip`、`el-message-box` 都不用重新学，全是同一套。

**方法论上的一句**：流行答案的**结论**可能碰巧对，**理由**却是错的。理由错了，下一题就会推错（本篇第八节就是那道下一题）。所以**依赖库的行为要翻 `node_modules` 查到那一行**，并连版本号一起记 —— 规则见 `../../讲解规则.md` 第五节。

**换版本后怎么重查**（本篇结论的复查清单）：

```bash
cd process-front
node -p "require('./node_modules/element-plus/package.json').version"
grep -n "appendToBody\|appendTo" node_modules/element-plus/es/components/dialog/src/dialog.mjs
grep -n "Teleport\|vShow" node_modules/element-plus/es/components/dialog/src/dialog.vue_vue_type_script_setup_true_lang.mjs
grep -n "rendered" node_modules/element-plus/es/components/dialog/src/use-dialog.mjs
grep -o "\.el-overlay{[^}]*}" node_modules/element-plus/dist/index.css
```

---

## 十、往下可以再挖的

1. **层叠上下文与 `z-index`** —— 5.2 第 2 条只给了结论。完整规则（哪些属性会创建层叠上下文、为什么 `z-index:99999` 会失效）够单独一篇，是 P5 BPMN 设计器**一定会撞上**的（画布 + 浮层 + 属性面板三层叠）
2. **`scoped` 与 `:deep()` 的编译产物** —— 亲眼看看 `data-v-xxx` 是怎么加上去的、`:deep()` 编译成了什么选择器。看一眼就再也不会记混
3. **CSS 定位五种值的完整图景** —— `static` / `relative` / `absolute` / `fixed` / `sticky`，以及"包含块"这个贯穿概念。4.3 只讲了 `fixed` 一种
4. **`v-if` vs `v-show` 的取舍** —— 4.1/4.2 里两者同时出现了，正好是现成的教材
5. **Vue 响应式的依赖收集机制** —— 第二节只讲到"名单"这一层。再往下是 `Proxy` 的 `get`/`set` 拦截、`effect` 与 `track`/`trigger`。这条能接上 `原生控件的外衣与el-switch.md` 讲的"变量同步更新、DOM 异步更新"
