# 原生控件的外衣 与 el-switch 逐字段拆解（答疑笔记）

> 由答疑 CLI 整理。触发点：`views/process/index.vue:5-9` 那段 `<el-switch>`，每个字段什么意思、值分别代表什么？
> **这是一次深挖回访**——`v-model双向绑定.md` 和 `change事件.md` 当初都是被这同一个组件触发的，但那两篇是从"用法"讲的。这次把源码翻开，验证那两篇的说法，并回答一个当时没能回答的问题：**`@change` 里能不能读到 `v-model` 的新值？**
> 前置：`模板语法-冒号与@.md`、`v-model双向绑定.md`、`change事件.md`。姊妹篇：`受控组件与el-pagination.md`、`配置型子组件与el-table.md`。
> 环境：Vue 3.5.39 / Element Plus 2.14.2。源码行号指
> `node_modules/element-plus/es/components/switch/src/` 下的 `switch.mjs`（props）与 `switch.vue_vue_type_script_setup_true_lang.mjs`（逻辑，下文简称 **`switch.vue.mjs`**）。**升级 EP 后行号会变，认代码不认行号。**

本篇的可复用知识是：**这类组件不是"画"出来的，是"藏一个原生控件 + 在上面盖一层皮"。** `el-checkbox`、`el-radio`、`el-select` 全是同一套。知道这一点，很多"为什么点不动/为什么 tab 键能选中/为什么 E2E 测试选不到元素"的怪事就都通了。

---

## 一、三个写法，三个类别

```html
<el-switch
    v-model="latestOnly"                ← ① 指令（v- 开头，无简写）：双向绑定语法糖
    active-text="只看最新版本"           ← ② 静态属性：原样传字符串
    @change="handleLatestChange"        ← ③ v-on：订阅组件发出的 change 事件
/>
```

`active-text` **没有冒号**，传的就是「只看最新版本」这几个字。`@change` 是 `v-on:change`。详见 `模板语法-冒号与@.md`。

`v-model` 属于第四类——像 `v-if`／`v-for`／`v-loading` 一样**没有简写的指令**。但它和别的指令不同：**它会被编译器展开成一个 prop + 一个事件监听**，见第三节。

---

## 二、逐字段

### `v-model="latestOnly"` —— 开关状态与变量绑在一起

绑的变量是 `const latestOnly = ref(false)`（`index.vue:72`），它最终被送进请求参数：`pageDefinitions(current.value, size.value, latestOnly.value)`（`index.vue:77`）。

对应的 prop 声明（`switch.mjs:15-22`）：

```js
modelValue: { type: [Boolean, String, Number], default: false }
```

**注意类型是三选一**，不只是布尔——原因见下面 `active-value`。

### `active-text="只看最新版本"` —— 开关右边那行字

声明：`activeText: { type: String, default: "" }`（`switch.mjs:71-74`）。

**⚠️ 这里有个真实误解，EP 官方文档的措辞是 "text displayed when in `on` state"，容易读成"打开时才显示这行字"。看渲染代码（`switch.vue.mjs:186-195`）：**

```js
!__props.inlinePrompt && (__props.activeIcon || __props.activeText || _ctx.$slots.active)
  ? createElementBlock("span", { class: normalizeClass(labelRightKls.value) }, ...)
  : createCommentVNode("v-if", true)
```

渲染条件里**根本没有 `checked`**——只要 `active-text` 非空就一直渲染。变化的只是 class（`switch.vue.mjs:58-62`）：

```js
const labelRightKls = computed(() => [ns.e("label"), ns.em("label", "right"), ns.is("active", checked.value)]);
```

**所以"只看最新版本"这几个字是常驻的，开关打开时只是颜色变深（多一个 `is-active` class）。** 这也正是我们想要的效果——它在这里就是个说明标签。

配套还有 `inactive-text`（渲染在开关**左边**，`switch.vue.mjs:145-154`）。两边都写就是「关 [开关] 开」那种样式。我们只写了右边。

> 唯一会"互斥显示"的是 `inline-prompt` 模式（`switch.vue.mjs:158-172`）——文字塞进滑轨内部，那时才 `!checked ? 显示 inactive : 显示 active`，而且**只渲染第一个字**（`switch.mjs:49` 的注释：only the first character will be rendered）。
>
> 另外 `active-icon` 会**顶掉** `active-text`（`switch.vue.mjs:192` 的条件是 `!__props.activeIcon && __props.activeText`），想同时要图标和文字得用 `#active` 插槽。

### `@change="handleLatestChange"` —— 用户拨动时它喊你

`change` 是组件**自己声明的**事件（`switch.mjs:134`），不是原生 DOM 的 change。声明了就是组件事件，不会再透传给根元素。

事件带一个参数：**新的值**（`switch.vue.mjs:84`：`emit(CHANGE_EVENT, val)`）。我们的 handler 没接（`index.vue:131`）：

```ts
function handleLatestChange() {
  current.value = 1
  loadList()
}
```

**这样写能不能拿到正确的值？** 这是本篇最关键的问题，第四节专门回答。

### 三个没写、但值得知道的

| prop | 默认 | 什么时候需要 |
|---|---|---|
| `active-value` / `inactive-value` | `true` / `false`（`switch.mjs:85-103`） | 后端字段不是布尔时。比如 `:active-value="'Y'" :inactive-value="'N'"` 或 `1`/`0`——**这就是 `modelValue` 类型声明成 `[Boolean, String, Number]` 的原因** |
| `before-change` | 无 | **拨动前二次确认**。返回 `false` 或 rejected 的 Promise 就取消切换（`switch.vue.mjs:90-105`）。比"在 `@change` 里弹窗，用户取消再改回去"好——后者会先闪一下 |
| `loading` / `disabled` | `false` | 请求期间锁住开关。`loading` 为真时**自动连带 disabled**（`switch.vue.mjs:42-44`），一个 prop 顶两个 |

> 还有个隐藏校验（`switch.vue.mjs:71-76`）：如果 `modelValue` 既不等于 `activeValue` 也不等于 `inactiveValue`，控制台报警告并**强制把值改成 `inactiveValue`**。我们 `ref(false)` 恰好等于默认的 `inactiveValue`，不会触发。

---

## 三、机制①：`v-model` 的真面目（源码验证）

`v-model双向绑定.md` 里说过"它是 `:绑值 + @监听回写` 的语法糖"。现在可以坐实了。

编译器把

```html
<el-switch v-model="latestOnly" />
```

展开成

```html
<el-switch :model-value="latestOnly" @update:model-value="$event => (latestOnly = $event)" />
```

组件那边（`switch.vue.mjs:81-89`，源码原文）：

```js
const handleChange = () => {
  const val = checked.value ? props.inactiveValue : props.activeValue;   // 取反
  emit(UPDATE_MODEL_EVENT, val);     // = emit('update:modelValue', val)
  emit(CHANGE_EVENT, val);           // = emit('change', val)
  emit(INPUT_EVENT, val);            // = emit('input', val)
  nextTick(() => { input.value.checked = checked.value });
};
```

（三个常量的真身在 `constants/event.mjs:2-4`：`"update:modelValue"` / `"change"` / `"input"`。）

**它一次发三个事件**，`update:modelValue` 打头。而组件自己的显示状态是从 prop 算出来的（`switch.vue.mjs:70`）：

```js
const checked = computed(() => actualValue.value === props.activeValue);   // actualValue 来自 props.modelValue
```

**它不存状态。** 和 `el-pagination` 是同一个套路（见 `受控组件与el-pagination.md`）——组件只负责显示和喊，值住在你的 ref 里。

> **两个库内的严格程度不同，值得对比一下：**
> - `el-pagination`：传了 `current-page` 却不监听 `current-change` → **整个组件不渲染**（`assertValidUsage`），错得很响；
> - `el-switch`：不写 `v-model` → 点了没反应，**静默不动**，不报错。因为 `checked` 恒等于初始 prop，永远不变。
>
> 后者更难查。**开关点不动的第一嫌疑就是 `v-model` 忘了写或者写错了变量。**

---

## 四、机制②：为什么 `handleLatestChange` 不接参数也是对的

这是本篇最有实用价值的一节，也是 `change事件.md` 当初没能回答的问题。

**担心是合理的**：`loadList()` 里读的是 `latestOnly.value`。如果 `change` 事件比 `v-model` 的回写**更早**触发，那第一次点开关时读到的就是旧值——你会看到"开关已经打开了，但列表还是旧的，再点一次才对"。这是个非常经典的 off-by-one-click bug。

**看源码，顺序是有保证的**（`switch.vue.mjs:83-84`）：

```js
emit(UPDATE_MODEL_EVENT, val);     // ← 第 83 行，先
emit(CHANGE_EVENT, val);           // ← 第 84 行，后
```

而 **`emit` 是同步的**——它就是去 props 里找到 `onUpdate:modelValue` 这个函数并**立即调用**，不是往队列里丢消息。所以完整时序是：

```
你点了开关
  ↓ switchValue() → handleChange()
  ↓ 第 83 行 emit('update:modelValue', true)
  ↓   └→ 同步调用 $event => (latestOnly = $event)
  ↓      └→ latestOnly.value = true          ← ✅ 变量此刻已经是新值
  ↓ 第 83 行返回
  ↓ 第 84 行 emit('change', true)
  ↓   └→ 同步调用 handleLatestChange()
  ↓      └→ current.value = 1
  ↓      └→ loadList() → 读 latestOnly.value → 读到 true ✅
```

**结论：`@change` 的 handler 里读 `v-model` 绑的变量，读到的一定是新值。** 我们这段代码是对的。

**但更明确的写法是直接接参数**——事件本来就把新值送过来了：

```ts
function handleLatestChange(val: boolean) {
  current.value = 1
  loadList()          // loadList 内部仍读 latestOnly.value，val 在这里只是让读者一眼看懂
}
```

### 两个必须分清的"顺序"

| | 是同步的吗 | 结论 |
|---|---|---|
| **响应式变量（ref.value）的更新** | ✅ 同步 | `emit` 返回时 `latestOnly.value` 已经是新值 |
| **DOM 的更新** | ❌ 异步（下一个 tick） | change handler 里立刻读 DOM，读到的还是旧画面；要读得 `await nextTick()` |

EP 自己就踩着这条线写代码——`switch.vue.mjs:86-88` 那个 `nextTick` 就是在等 DOM。

> **和 `async-await与JS单线程.md` 的区别，别混**：那篇讲的是"`await` 挂起函数、后面的代码要等"，处理的是**异步**顺序。这里从头到尾**没有任何异步**，就是一条普通的同步调用栈：`handleChange` → `emit` → 你的赋值函数 → 返回 → `emit` → 你的 handler。同样是"顺序有保证"，但机制完全不同。

---

## 五、机制③：它其实是一个被藏起来的 `<input type="checkbox">`

把 `switch.vue.mjs:122-196` 的渲染函数翻译回 HTML，实际长这样：

```html
<div class="el-switch is-checked" @click.prevent="switchValue">   ← 你点的是这个 div
  <input class="el-switch__input" type="checkbox" role="switch"   ← 真正的原生控件
         aria-checked="true" true-value="true" false-value="false"
         @change="handleChange" @keydown.enter="switchValue">
  <span class="el-switch__core">                                  ← 你看到的滑轨
    <div class="el-switch__action"></div>                         ← 你看到的圆点
  </span>
  <span class="el-switch__label el-switch__label--right is-active">只看最新版本</span>
</div>
```

那个 `<input>` 被 CSS 藏了（`theme-chalk/index.css`，源码原文）：

```css
.el-switch__input { opacity: 0; width: 0; height: 0; margin: 0; position: absolute }
```

**注意是 `opacity: 0` 而不是 `display: none`——这是刻意的。** `display: none` 的元素**无法获得焦点**，那样 Tab 键就跳不到它、键盘操作全废、屏幕阅读器也读不到。用 `opacity: 0` + 零尺寸，元素在无障碍树里仍然存在。

**留着这个原生 input 换来三样东西**：① Tab 键可聚焦、空格/回车可操作；② 屏幕阅读器认得 `role="switch"` + `aria-checked`；③ 放进原生 `<form>` 里能被一起提交（靠 `name` prop）。

### 两个值得注意的实现细节

**`@click.prevent`**（`switch.vue.mjs:125`：`withModifiers(switchValue, ["prevent"])`）
就是 `模板语法-冒号与@.md` 第五节讲的那个 `.prevent` 修饰符。为什么要 prevent：点击外层 div 会连带触发内部 checkbox 的默认切换行为，那样状态就有两个来源了。**prevent 掉，只走 JS 这一条路。**

**发完事件后的 `nextTick` 回拨**（`switch.vue.mjs:86-88`）：

```js
nextTick(() => { input.value.checked = checked.value });
```

`checked` 是从 **prop** 算出来的。这句的意思是：**下一个 tick，强行把原生 checkbox 的状态拨回和 prop 一致。** 如果父组件没有更新 `modelValue`（比如你没写 `v-model`，或者 `before-change` 拒绝了），原生控件已经自己翻了的那一下会被**拨回原位**。

这就是"组件不存状态"在物理层面的执行——**唯一真相是 prop，DOM 敢不一致就被拉回来。**

---

## 六、诞生背景：为什么要藏一个原生控件

**旧世界一 · 原生 checkbox 改不动样式。**
`<input type="checkbox">` 的外观由操作系统和浏览器决定，Chrome、Firefox、Safari、IE 各画各的，CSS 几乎无法定制（连大小都难改）。设计稿上那个圆润的滑动开关，用原生控件**做不出来**。

**旧世界二 · 纯 CSS 时期（2013 年前后的 CodePen 神技）。**

```html
<input type="checkbox" id="s" class="hidden">
<label for="s" class="slider"></label>      <!-- 点 label 会连带切换 input -->
```
```css
.hidden { position: absolute; opacity: 0 }
input:checked + label .dot { transform: translateX(20px) }   /* 靠兄弟选择器画皮 */
```

**思路已经是"藏原生 + 画皮"了**，`el-switch` 继承的就是这个。痛点：状态只在 DOM 里（`input.checked`），要读要写都得 `querySelector`；没法带业务值（只有 true/false）；一个页面十个开关就是十份复制粘贴的 CSS。

**旧世界三 · jQuery 插件（bootstrap-switch，2012）。**
`$('#s').bootstrapSwitch()` 自动生成一堆 div 包住原生 input。解决了复用，但**状态仍然住在插件里**——要联动（比如"打开开关就重新查询并回到第一页"）只能 `$('#s').on('switchChange', ...)` 再手动去改别处，两份状态迟早不同步。这就是 `受控组件与el-pagination.md` 第四节说的同一个痛点。

**新方案 · 组件库。**
外壳沿用"藏原生 + 画皮"（无障碍和键盘操作照单全收），但**状态搬出组件、交给 `v-model`**；事件规范化成 `update:modelValue` + `change`；值可以是任意类型（`active-value`）；`before-change` 提供拦截点。于是

```ts
function handleLatestChange() { current.value = 1; loadList() }
```

这种联动可以直接写在页面里——**在 jQuery 时代这需要去翻插件文档找它的事件名，还得祈祷它暴露了你要的钩子。**

**代价**（真实存在，不是走过场）：
- **DOM 结构变复杂**——一个开关五层节点。调试时 `document.querySelector('.el-switch input')` 找到的是那个隐形的，而**点击它不生效**（点击处理器在外层 div 上）。写 E2E 测试时这是高频坑，得点 `.el-switch` 或 `.el-switch__core`。
- **"看得见的"和"能操作的"是两个元素**——初学者容易被绕进去。

---

## 七、动手实验（改一行看效果，看完改回来）

**实验 1 · 验证「不写 v-model 就静默不动」**
把 `v-model="latestOnly"` 删掉 → **开关点了纹丝不动，控制台也不报错**。这就是第三节说的"错得很安静"。再改成 `:model-value="latestOnly"`（只传值、不监听）→ 一样不动。加回 `v-model` → 恢复。**这个实验做完，"组件不存状态"就不再是一句话了。**

**实验 2 · 验证 `active-text` 是常驻的**
观察开关关闭时——「只看最新版本」这几个字**仍然在**，只是颜色浅。打开时变深（多了 `is-active` class，可在 DevTools 里看到 class 变化）。再加一个 `inactive-text="全部版本"` → 开关左边多出一行字，两边同时常驻。

**实验 3 · 验证 `@change` 里读到的是新值**
把 handler 临时改成：

```ts
function handleLatestChange(val: boolean) {
  console.log('事件参数 =', val, '  变量 latestOnly =', latestOnly.value)
  current.value = 1
  loadList()
}
```

点一下 → 两个值**一模一样**。这就是第四节那条时序的直接证据。

**实验 4 · 感受 `before-change` 的拦截**
临时加上：

```html
<el-switch v-model="latestOnly" active-text="只看最新版本"
           :before-change="() => window.confirm('确定切换？')" @change="handleLatestChange" />
```

点开关 → 先弹确认框；点「取消」→ **开关一动不动**（`switch.vue.mjs:104` 的 `else if (shouldChange)` 直接不走 `handleChange`），`@change` 也不触发。对比一下"先切换再弹窗，取消后改回去"会闪一下，差别很明显。

**实验 5 · 找到那个隐形的 input**
DevTools 里展开 `.el-switch`，能看到 `<input type="checkbox" class="el-switch__input">`。选中它，Styles 面板里就是 `opacity: 0; width: 0; height: 0`。然后**点击页面空白处，按 Tab 键**——焦点能跳到开关上（有聚焦轮廓），按空格能切换。这就是留着原生 input 的意义。

---

## 八、回到本项目：三处值得注意

**1. 有一个真实的竞态隐患：请求期间开关没锁。**

`handleLatestChange` 里直接 `loadList()`，而开关在请求返回前**可以被反复点**。快速点三下会并发三个请求，而**响应回来的顺序不保证**——如果先发的后回，`list` 会被旧结果覆盖，页面显示的内容和开关状态对不上。解法是加一个 prop：

```html
<el-switch v-model="latestOnly" active-text="只看最新版本"
           :loading="loading" @change="handleLatestChange" />
```

`loading` 为真时组件**自动连带 disabled**（源码见下篇 §4.1），一个 prop 顶两个，还会显示转圈图标。而 `loading` 这个 ref 已经在 `loadList()` 里管好了（`index.vue:75` 置 true、`:83-85` 的 `finally` 置 false），**接上即可，零额外代码**。

> 📌 **这一条已抽成单独一篇：[`请求竞态与控件禁用.md`](./请求竞态与控件禁用.md)**（2026-08-10）。它牵扯到三个控件两个页面，藏在本篇里位置太偏、找不到。那边讲全了：不加的确切后果（**静默错位，不报错**）、响应为什么会乱序、jQuery 时代手动 disable 的痛点、`switch.vue_..._lang.mjs:42-44` 的源码为证、**为什么加 `await` 治不了**，以及三个可跑实验。**本条只留结论，细节去那篇。**

**2. `current.value = 1` 这句是必须的，别删。**
切换筛选条件后总条数会变，如果停在第 3 页而新结果只有 1 页，会看到空表格。这和 `handleDelete` 里那句 `if (list.value.length === 1 && current.value > 1) current.value -= 1`（`index.vue:116-118`）是同一类考虑。

**能这么写，正是"受控"换来的自由**——页码住在我们自己的 `current` ref 里，随手就能改。`受控组件与el-pagination.md` 第四节讲的那个 jQuery 痛点（"页码在插件肚子里，你改不动它"），这句代码就是它的反面证据。

**3. handler 建议接一下参数**：`function handleLatestChange(val: boolean)`。行为完全一样（第四节已证明现在的写法是对的），但读代码的人不用去推导时序才敢确信没问题。

---

## 九、常见误解速查

| 误解 | 实际 |
|---|---|
| `active-text` 只在打开时显示 | ❌ **一直显示**，打开时只是多一个 `is-active` class（颜色变深）。只有 `inline-prompt` 模式才互斥 |
| `@change` 可能比 `v-model` 回写更早 | ❌ 源码里 `emit('update:modelValue')` 在**第 83 行**、`emit('change')` 在**第 84 行**，且 `emit` 是同步的。handler 里读到的一定是新值 |
| change handler 里能立刻读到更新后的 DOM | ❌ **变量是同步更新的，DOM 是异步的**。要读 DOM 得 `await nextTick()` |
| 不写 `v-model` 只是拿不到值 | ❌ **开关会完全不动**，且不报错。因为 `checked` 是从 prop 算的，prop 不变它就不变 |
| `el-switch` 是一堆 div 画出来的 | ❌ 里面有个**真正的 `<input type="checkbox">`**，用 `opacity:0` 藏着（不是 `display:none`，那样就没法聚焦了） |
| 点 `.el-switch input` 就能模拟点击 | ❌ 点击处理器在**外层 div** 上（`@click.prevent`）。E2E 里要点 `.el-switch` 或 `.el-switch__core` |
| `v-model` 只能绑布尔值 | ❌ 配 `active-value` / `inactive-value` 可以绑 `'Y'`/`'N'`、`1`/`0`——所以 `modelValue` 声明的是 `[Boolean, String, Number]` |
| 要二次确认就在 `@change` 里弹窗 | ❌ 那样会**先切换再回滚，闪一下**。用 `before-change`，它在切换**之前**拦截 |
| `loading` 只是显示个转圈 | ❌ 它**连带把组件 disable 掉**（`switch.vue.mjs:42-44`） |

---

## 十、一句话总结

> `v-model="latestOnly"` 把开关状态和你的 ref 绑在一起——**组件自己不存状态**，`checked` 是从 prop 算出来的，不写 `v-model` 它就纹丝不动；`active-text` 是开关旁边**常驻**的说明文字（打开时只变颜色，不是"打开才显示"）；`@change` 是它拨动时喊你一声，并把**新值**当参数送过来。
> **执行顺序有源码保证**：`emit('update:modelValue')` 在前、`emit('change')` 在后，且 `emit` 是同步调用——所以 change handler 里读 `latestOnly.value` 读到的一定是新值，我们这段代码是对的（但注意：**变量同步更新、DOM 异步更新**）。
> 底层它是一个 `opacity:0` 藏起来的 `<input type="checkbox">` + 一层用 div/span 画的皮——藏而不删，是为了保住键盘操作和屏幕阅读器。

---

## 十一、往下可以再挖的

- **立刻能做的一件事**：给开关加 `:loading="loading"`（见第八节 1），顺手消掉一个真实的并发竞态，零额外代码。
- **`v-model` 的完整形态**：Vue 3 支持 `v-model:foo="bar"` 绑多个值（`el-pagination` 就有 `v-model:current-page`），以及 `.trim` / `.number` / 自定义修饰符。本篇看到的是最基础的单值形态。
- **`before-change` 的 Promise 用法**：`:before-change="() => ElMessageBox.confirm('...')"`——`ElMessageBox.confirm` 返回 Promise，用户取消时 reject，正好被 `switch.vue.mjs:101` 的 `.catch` 接住并取消切换。**比 `handleDelete` 里"先 await 确认再执行"的写法更贴合开关场景**，将来把挂起/激活改成开关时用得上。
- **表单集成**：`switch.vue.mjs:79` 那句 `formItem?.validate?.("change")`——放进 `<el-form-item>` 里时会自动触发校验，靠的是 `provide/inject`。P6 表单设计器要**自己实现**这套父子通信，那时会回来看这一行。
- **"藏原生 + 画皮"的其它实例**：`el-checkbox`、`el-radio`、`el-select`（藏一个 input 用来聚焦和输入搜索）、`el-upload`（藏一个 `<input type="file">`，因为文件选择框**必须**由真实 input 触发，JS 造不出来）。最后这个是这套模式最不得已、也最能说明问题的例子。
