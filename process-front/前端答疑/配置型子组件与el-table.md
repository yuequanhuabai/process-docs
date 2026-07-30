# 配置型子组件 与 el-table 逐字段拆解（答疑笔记）

> 由答疑 CLI 整理。触发点：`views/process/index.vue:13-37` 那段 `<el-table>`，每个字段什么意思、值分别代表什么？
> 前置：`模板语法-冒号与@.md`（`:` `@` `#` 是什么）、`插槽slot与作用域插槽.md`（`#default="{ row }"`）。
> 姊妹篇：`受控组件与el-pagination.md`（同一页的另一半，讲**受控组件**）。
> 环境：Vue 3.5.39 / Element Plus 2.14.2。下文源码行号指
> `process-front/node_modules/element-plus/es/components/table/src/` 下各文件（**升级 EP 后行号会变，认代码不认行号**）。

本篇的可复用知识是**配置型子组件**这个模式——`<el-table-column>` **根本不渲染你看到的那一列**，它只是把一份"列配置"注册进父表格。`el-select` 里的 `<el-option>`、`el-tabs` 里的 `<el-tab-pane>`、`el-steps` 里的 `<el-step>` 全是同一套。认出这个模式，这一大类组件就不用一个个读文档了。

---

## 一、先把这一堆写法分成四类

```html
<el-table :data="list" v-loading="loading" border style="width: 100%">
```

| 写法 | 类别 | 传过去的是 |
|---|---|---|
| `:data="list"` | **`v-bind` 动态绑定** | 变量 `list` 的值（一个数组） |
| `v-loading="loading"` | **指令**（不是 prop！） | —— 见下文 |
| `border` | **静态属性 + Boolean 转换** | `true` |
| `style="width: 100%"` | **原生 HTML 属性** | 字符串，透传到根元素 |

`模板语法-冒号与@.md` 里讲了 `:` `@` `#` 三个简写。这里出现了**第四类**：像 `v-loading` `v-if` `v-for` 这种**没有简写的指令**——`v-` 开头、写全称。指令做的是"对这个元素施加某种行为"，跟"给组件传 prop"是两回事。

---

## 二、`<el-table>` 上的四个东西

### `:data="list"` —— 有哪些行

声明是 `data: { type: Array, default: () => [] }`（`table/defaults.mjs:10-13`）。表格遍历这个数组，**一个元素画一行**。

值来自 `loadList()` 里的 `list.value = page.records`（`index.vue:78`），也就是后端 `IPage` 的 `records`。

> 和分页器那边正好凑成一对：`records` 喂给表格画行，`total` 喂给分页器算页数。这就是 Day 1 定下 `PageResult<T>` 契约的用处。

### `v-loading="loading"` —— 一层遮罩，跟表格无关

**它不是 `el-table` 的 prop**，是 ElLoading 提供的**全局指令**（`components/loading/src/directive.mjs`）：

```js
const vLoading = {
  mounted(el, binding) { if (binding.value) createInstance(el, binding) },   // 真 → 盖遮罩
  updated(el, binding) {
    if (!binding.value) { instance?.instance.close(); ... return }           // 变假 → 收遮罩
    ...
  }
}
```

它往**这个 DOM 元素**上盖一层带转圈图标的遮罩，`loading` 变 `false` 就撤掉。所以：

- 换成 `<div v-loading="loading">` 一样能用，**任何元素都行**；
- `loading` 的开关在 `loadList()` 里（`index.vue:75` 置 true、`:81` 的 `finally` 置 false）——`finally` 保证请求失败时遮罩也会收掉，这个写法是对的；
- 还能传对象定制：`v-loading="{ text: '加载中', background: 'rgba(0,0,0,.6)' }"`（`directive.mjs:18-29`）。

### `border` —— 无值属性 = `true`

声明是 `border: Boolean`（`table/defaults.mjs:41`）。作用是**画竖向分隔线**（默认只有横线）。

**为什么不写 `="true"` 也生效**：HTML 里 `<input disabled>` 这种无值属性传的是空字符串 `""`，而 Vue 对声明为 `Boolean` 的 prop 有**特殊转换**——`""` 转成 `true`。这是 Vue 专门为了贴合 HTML 习惯做的（回顾 `模板语法-冒号与@.md` 第三节：如果没有这条规则，`""` 是假值，`border` 反而不生效）。

> **白送的功能**：`el-table-column` 的 `resizable` 默认就是 `true`，而它的注释写着 "works when `border` of `el-table` is `true`"（`table-column/defaults.mjs`）。也就是说——**我们这张表现在已经可以用鼠标拖动列的分隔线改列宽了**，因为 `border` 开着。可以立刻去试。

### `style="width: 100%"` —— 原生属性，透传

不是 prop，是原生 HTML 属性。组件没声明的属性会**自动落到根元素上**（Vue 叫「attribute fallthrough / 透传」）。`class` 和 `style` 还有特殊待遇：**与组件自己的合并而不是覆盖**。

`el-table` 本来就是块级 `div`、天然占满宽度，这行严格说可以不写，写上是为了显式和保险。

---

## 三、`<el-table-column>` 逐字段

字段分两类：**取值类**（这一格显示什么）和 **排版类**（这一列多宽、怎么放）。

### 取值类

#### `prop="name"` —— 从 row 的哪个字段取值

没有插槽时，单元格内容由这个函数产出（`config.mjs:115-120`，源码原文）：

```js
function defaultRenderCell({ row, column, $index }) {
  const property = column.property;
  const value = property && getProp(row, property).value;
  if (column && column.formatter) return column.formatter(row, column, value, $index);
  return value?.toString?.() || "";
}
```

三个要点：

1. **`getProp` 底层是 lodash 的 `get`**（`utils/objects.mjs:6`）→ **支持点路径**：`prop="user.info.name"` 合法，中间某层是 `undefined` 也不会炸。
2. **最后一句 `value?.toString?.() || ""`**——所以 `suspended: false` 会被渲染成字面量 `"false"` 四个字母，`version: 0` 会渲染成 `"0"`。**这正是状态列不能用 `prop="suspended"` 的原因**，见下面第五节。
3. `formatter` 优先——想把时间戳格式化成日期，不用写插槽，给个 `:formatter` 函数就行，比插槽轻。

> `prop` 有个别名 `property`，两个都能用（`table-column/index.vue…mjs:39`：`property: props.prop || props.property`）。统一用 `prop`。

#### `label="流程名称"` —— 表头那行字

渲染成表头的文本节点（`table-column/render-helper.mjs:74`：`createTextVNode(column.label)`）。

想在表头放图标、加筛选按钮，用 `#header` 插槽顶掉它（`render-helper.mjs:70-73`）。

### 排版类

#### `width="80"` vs `min-width="140"` —— 最容易混的一对

**`width` 是"我就这么宽，一寸不让"；`min-width` 是"至少这么宽，剩余空间按比例分我一份"。**

源码里的分配逻辑（`table-column/render-helper.mjs:37-44`）：

```js
if (realWidth.value)  column.width = realWidth.value;
if (realMinWidth.value) column.minWidth = realMinWidth.value;
if (!realWidth.value && realMinWidth.value) column.width = void 0;   // 只给 min-width → 宽度不固定
if (!column.minWidth) column.minWidth = 80;                          // ← 默认最小宽 80
column.realWidth = Number(isUndefined(column.width) ? column.minWidth : column.width);
```

代进我们这张表：

| 列 | 写法 | 结果 |
|---|---|---|
| 流程名称 | `min-width="140"` | 保底 140，参与瓜分剩余空间 |
| 流程 Key | `min-width="140"` | 同上 |
| 版本 | `width="80"` | 死死 80px |
| 状态 | `width="90"` | 死死 90px |
| 资源名 | `min-width="200"` | 保底 200，参与瓜分（权重最大） |
| 操作 | `width="180"` | 死死 180px |

即：**350px 被三个固定列吃掉，剩下的宽度按 140:140:200 的比例分给另外三列。** 窗口拉宽时，只有这三列会变宽。

按比例分配的前提是 `fit` 为真——它默认就是 `true`（`table/defaults.mjs:30-33`）。

> **两个真实的坑**（`util.mjs:110-125`）：
> `parseWidth` 做的是 `Number.parseInt(width, 10)`，NaN 就退回 `""`。
> ① `width="80px"` 能工作（`parseInt` 会忽略 `px`）——但别这么写，容易让人误以为支持 CSS 单位；
> ② **`width="20%"` 会被解析成 20（像素）**，不是百分比，直接把列压扁。表格列宽**不支持百分比**。
> ③ `min-width` 解析失败时兜底成 80（`:122`），不是 0。

#### `show-overflow-tooltip` —— 单行截断 + 悬浮显示全文

不加：长文本**换行**，这一行会变高，整张表参差不齐。
加上：内容压成一行、超出显示 `…`，鼠标悬停弹出完整内容。

实现（`render-helper.mjs:103-106`）：给 `.cell` 加上 tooltip class，并**写死一个内联宽度**：

```js
props.style = { width: `${(data.column.realWidth || Number(data.column.width)) - 1}px` };
```

有了确定宽度，CSS 的 `text-overflow: ellipsis` 才能生效。

**它的声明很特别**：`{ type: [Boolean, Object], default: void 0 }`——默认是 `undefined` 而不是 `false`，为的是做**三级配置回退**（`table-column/index.vue…mjs:33`）：

```js
const showOverflowTooltip = isUndefined(props.showOverflowTooltip)
  ? parent.props.showOverflowTooltip ?? globalConfig.value?.showOverflowTooltip   // 列没配 → 看表格 → 看全局
  : props.showOverflowTooltip;
```

也就是：**列上配 > 表格上配 > 全局 config-provider 配**。想让全表都截断，在 `<el-table>` 上写一次就够，不用每列写。这是个值得记住的配置回退套路。

我们只给 `resourceName` 加了——因为资源名是 `xxx.bpmn20.xml` 这种长字符串，其它列都短。判断是对的。

#### `fixed="right"` —— 钉在右边，不随横向滚动

声明是 `[Boolean, String]`：`fixed`（无值）= `true` = 钉左边；`fixed="right"` = 钉右边。

**它做的事比"加个样式"重得多**（`store/watcher.mjs:85-104`）：

```js
fixedColumns.value      = _columns.value.filter(c => [true, "left"].includes(c.fixed));
rightFixedColumns.value = _columns.value.filter(c => c.fixed === "right");
const notFixedColumns   = _columns.value.filter(c => !c.fixed);
originColumns.value = Array.from(fixedColumns.value).concat(notFixedColumns).concat(rightFixedColumns.value);
...
isComplex.value = fixedColumns.value.length > 0 || rightFixedColumns.value.length > 0;
```

**列会被重新排序**：所有 fixed-left 提到最前，所有 fixed-right 推到最后，**不管你在模板里写在第几个**。我们的操作列本来就写在最后，所以看不出重排——但如果哪天把它挪到中间去写，显示位置**仍然在最右**。

另外 `isComplex` 变成 `true` 会让表格进入更复杂的渲染路径（额外的滚动条同步、独立的固定列层，`layout-observer.mjs:56`）。

> **没有横向滚动条时，`fixed` 看不出任何效果**，但代价照付。我们这张表在宽屏下大概率不会横向滚动——现在写着是为窄屏和以后加列做准备，合理。

---

## 四、机制：`<el-table-column>` 不渲染那一列

**这是整个组件最反直觉的一点，也是本篇最该带走的知识。**

看它的 `onMounted`（`table-column/index.vue_vue_type_script_setup_true_lang.mjs:84-90`）：

```js
onMounted(() => {
  const children = ... parent.refs.hiddenColumns?.children;               // ← hidden
  columnConfig.value.getColumnIndex = getColumnIndex;
  getColumnIndex() > -1 && owner.value.store.commit("insertColumn", columnConfig.value, ...);
});                                                     // ↑ 把自己 commit 进父表格的 store
```

和它的 render（`:97-118`）：

```js
const TableColumnRenderer = () => { ... return h("div", children) };   // 就渲染成一个 div
return (_ctx, _cache) => (openBlock(), createBlock(TableColumnRenderer));
```

拼起来是这样：

```
<el-table-column prop="name" label="流程名称" min-width="140" />
        ↓ onBeforeMount：把 props 揉成一份配置对象 column = { property, label, minWidth, renderCell, ... }
        ↓ onMounted：store.commit("insertColumn", column)      ← 注册进父表格
        ↓ 自身渲染 = 一个 div，塞进表格的 hiddenColumns 容器（隐藏，你看不见）
        ↓
真正画 <td> 的是 table-body：columns.value.map((column, cellIndex) => ...)   ← 遍历 store 里的配置
                                （table-body/render-helper.mjs:46）
```

**它是一份"声明"，不是一个"控件"。** 后端视角的类比：`<el-table-column prop="name" label="流程名称" width="140" />` 更像

```java
@Column(name = "name", label = "流程名称", length = 140)
private String name;
```

——你在声明字段元数据，真正建表、逐行写数据的是别的东西（ORM / table-body）。

组件卸载时还会 `store.commit("removeColumn", ...)`（`:91-94`），所以 `<el-table-column v-if="canDelete">` 这种条件列是能正常工作的：条件变假 → 卸载 → 从 store 里摘掉 → 表格重排。

**这个认知能解释三个常见困惑：**

1. **不能在列外面套 `<div>`**——列组件靠 `instance.parent` 一路往上找带 `tableId` 的祖先（`:20-24`），中间隔一层普通元素虽然还能找到，但 `onMounted` 里靠 `parent.refs.hiddenColumns.children` 算列序号（`:86-87`）就会错位。想动态生成列请用 `v-for` + `:key`，别套容器。
2. **DevTools 里组件树和 DOM 树对不上**——组件树里有六个 `ElTableColumn`，DOM 里却找不到对应节点，因为它们都在那个隐藏 div 里。
3. **列顺序不完全由模板决定**——见上面 `fixed` 那节的重排。

---

## 五、`#default="{ row }"`：什么时候必须用插槽

### 判定规则

看 `render-helper.mjs:88-95`：

```js
originRenderCell = originRenderCell || defaultRenderCell;
column.renderCell = (data) => {
  let children = null;
  if (slots.default) {
    const vnodes = slots.default(data);
    children = vnodes.some(v => v.type !== Comment) ? vnodes : originRenderCell(data);
  } else children = originRenderCell(data);
  ...
};
```

**有插槽走插槽，没插槽走 `defaultRenderCell`（即按 `prop` 取值）。** 所以：

- 前三列 + 资源名列：内容就是"把字段打印出来" → 只写 `prop`，不需要插槽；
- **状态列**：要显示的是 `el-tag` 组件、文字还要从 `false` 翻译成"挂起" → 必须插槽，`prop` 写了也没用，所以干脆不写；
- **操作列**：内容是两个按钮、还要绑 `@click` → 必须插槽，压根没有对应字段。

> 边角情况：如果插槽渲染出来**全是注释节点**（比如里面只有一个 `v-if` 且条件为假，Vue 会留下注释占位），`vnodes.some(v => v.type !== Comment)` 为假，**会回退到按 `prop` 取值**。知道有这条就行。

### `{ row }` 是从哪来的、里面还有什么

table-body 每画一格时组装这个对象（`table-body/render-helper.mjs:51-59`，源码原文）：

```js
const data = {
  store,
  _self: props.context || parent,
  column: columnData,
  row,          // ← 当前这一行的原始数据对象（就是 list 数组里的那个元素）
  $index,       // ← 行下标
  cellIndex,
  expanded
};
```

然后 `column.renderCell(data)` → `slots.default(data)`。所以 `#default="{ row }"` 是**对这个对象做解构**，只取了 `row` 一个键。想要更多就多解构几个：

```html
<template #default="{ row, $index, column }">
```

> **`$index` 的陷阱**：它是**当前页数据数组的下标，从 0 开始**，不是全局序号。翻到第 2 页，第一行的 `$index` 还是 `0`。想显示"第 11 条"必须自己算 `(current - 1) * size + $index + 1`。

### 一个很难查的坑：你的插槽会被空数据调用一次

`table-column/index.vue…mjs:97-115`：

```js
const TableColumnRenderer = () => {
  try {
    const renderDefault = slots.default?.({ row: {}, column: {}, $index: -1 });   // ← 空 row！
    ...                                        // 目的：探测插槽里有没有嵌套的 <el-table-column>（多级表头）
  } catch { return h("div", []); }             // ← 报错被吞掉
};
```

列组件为了判断"你是不是用插槽写了多级表头"，会**用一个空对象 `{}` 当 row 调用你的插槽函数一次**，`$index` 传 `-1`。

- 我们的状态列插槽里是 `row.suspended`，在 `{}` 上取值得到 `undefined`，三元走 `'success'` 分支，无害；
- **但如果你写了 `row.user.name` 这种深层访问，这次探测会抛 `TypeError`**——而它被 `try/catch` 吞了，页面照常显示，你只会觉得"偶尔莫名其妙"；
- **如果插槽里有副作用**（调了个函数、打了个日志），会莫名多执行一次，`$index === -1` 就是它的特征。

插槽里访问深层字段务必用可选链：`row.user?.name`。

---

## 六、诞生背景：为什么是"标签声明列"

**旧世界一 · 手写原生 `<table>`**

```html
<thead><tr><th>流程名称</th><th>版本</th></tr></thead>
<tbody><tr v-for="r in list"><td>{{ r.name }}</td><td>{{ r.version }}</td></tr></tbody>
```

痛点：**表头和单元格分两处写**，加一列要改两个地方、还要数着对齐；固定列、排序、列宽分配全得自己实现。

**旧世界二 · jQuery 时代的数组配置（DataTables / EasyUI，2008-2012）**

```js
$('#t').dataTable({
  columns: [
    { data: 'name', title: '流程名称', width: 140 },
    { data: null, title: '操作',
      render: function (d, t, row) {
        return '<button class="del" data-id="' + row.id + '">删除</button>';   // ← 拼 HTML 字符串
      } }
  ]
});
$(document).on('click', '.del', function () { ... });    // ← 事件只能靠委托，跟按钮定义隔了十万八千里
```

痛点：**单元格里想放个按钮，只能拼 HTML 字符串**——没有类型检查、没法复用组件、要手动转义防 XSS，事件还得靠委托远程绑定。定义和行为被硬拆成两半。

**Vue / Element Plus 的答案：把"列配置"写成模板的一部分。**

于是单元格里可以**直接写组件**、事件**就地绑定**：

```html
<template #default="{ row }">
  <el-button link @click="handleDelete(row)">删除</el-button>
</template>
```

`row` 由作用域插槽传进来，`handleDelete` 就是同文件里那个普通函数——**拼字符串的时代结束了**。

**代价**：`<el-table-column>` 成了一个"假组件"（第四节），带来 DevTools 对不上、不能随便套容器、初学者会以为它就是那一列。这是这套设计实打实的学习成本。

**横向对照 · React 的 antd Table 走回了数组配置**：

```jsx
columns={[{ dataIndex: 'name', title: '流程名称', width: 140 },
          { title: '操作', render: (_, row) => <Button onClick={() => del(row)}>删除</Button> }]}
```

因为 JSX 里返回组件本来就天经地义，不需要"标签声明"这一层。**又是同一个问题的两种答案**——跟 `模板语法-冒号与@.md` 里 Vue 的 `:` vs React 的 JSX 完全是同一条分叉：**Vue 想让模板保持 HTML 的样子，就得往 HTML 里塞表达力；React 直接把 HTML 搬进 JS，就不需要塞。**

---

## 七、动手实验（改一行看效果，看完改回来）

**实验 1 · 感受 `width` 和 `min-width` 的区别**
把版本列的 `width="80"` 改成 `min-width="80"`，然后**拖动浏览器窗口改宽度** → 版本列跟着变宽了（参与瓜分剩余空间）；改回 `width` → 无论窗口多宽，它死死 80px。**这个实验做完，这对属性就再也不会混。**

**实验 2 · 验证"没插槽就打印字段值"**
把状态列整段 `<template #default>` 删掉，改成 `<el-table-column prop="suspended" label="状态" width="90" />` → 单元格显示字面量 `false` / `true`。这就是 `value?.toString?.() || ""` 的效果，也是**为什么这一列非用插槽不可**。

**实验 3 · 感受 `show-overflow-tooltip`**
删掉资源名列的 `show-overflow-tooltip` → 长资源名换行，那一行明显变高、整张表参差不齐；加回来 → 一行 + `…` + 悬停提示。

**实验 4 · 验证 `fixed` 会重排列**
把操作列那一整段 `<el-table-column label="操作" ... fixed="right">` **剪切到第一列的位置**（`prop="name"` 那行之前）→ 页面上它**仍然显示在最右边**。这就是 `store/watcher.mjs:96` 那次 `concat` 重排。再把 `fixed="right"` 删掉 → 它立刻回到第一列。

**实验 5 · 看见 fixed 的真正用途**
把资源名列的 `min-width="200"` 改成 `min-width="1200"` 制造横向滚动条 → 左右拖动，**操作列钉在右边不动**。再删掉 `fixed="right"` 对比 → 它跟着滚走了。

---

## 八、回到本项目：五处值得注意

**1. 没有 `row-key`，行的 key 用的是数组下标。**
`table-body/render-helper.mjs:20-24`：

```js
const getKeyOfRow = (row, index) => {
  const rowKey = (parent?.props)?.rowKey;
  if (rowKey) return getRowIdentity(row, rowKey);
  return index;                                     // ← 没配就用下标
};
```

我们每次 `loadList()` 都是整页替换，用下标暂时没问题。但**将来加多选（`type="selection"` + `reserve-selection`）或行内编辑，必须补 `row-key="id"`**——EP 源码注释里明说 `row-key` 是 `reserve-selection` 的前提。`ProcessDefinition` 有 `id`（`api/process.ts:6`），加起来是一行的事。

**2. 列宽已经可以拖拽了。** `border` 为真 + `resizable` 默认 `true` → 用户能拖动表头分隔线改列宽。白送的功能，现在就能试。

**3. 没有 `height` / `max-height` → 没有固定表头。** 行数多了要整页往下滚，表头会滚出视野。P4 之后数据变多可以加 `max-height="500"`（注意：一加就会让表格进入 `fixed` 布局模式，`layout-observer.mjs:161`）。

**4. `class="process-page"` / `toolbar` 目前是空钩子。** `views/process/index.vue` 全文没有 `<style>` 块（文件到 136 行 `</script>` 结束），三个 class 都没有样式。参考样式在 `../process_manage/03-完整代码.md`。

**5. 仍在途的运行期 bug（编译不报错，点了才 404）：**

| 前端 | 后端真实路径 |
|---|---|
| `api/process.ts:22` → `/process-definition/{id}/suspended` | `ProcessDefinitionController.java:43` → `{definitionId}/suspend` |
| `api/process.ts:26` → `/process-definition/{id}/active` | `ProcessDefinitionController.java:50` → `{definitionId}/activate` |

`suspended` → `suspend`、`active` → `activate`，两处各改一个词。

> 顺带记一笔进度：`activateDefinition` 的命名已经两边一致了（`api/process.ts:25`），`onMounted(loadList)` 也补上了（`index.vue:135`）——Day 15 的编译错误已清。剩下的是这两个 URL、路由和菜单。

---

## 九、常见误解速查

| 误解 | 实际 |
|---|---|
| `<el-table-column>` 就是渲染出来的那一列 | ❌ 它渲染进一个**隐藏 div**，只把列配置 `commit` 进父表格的 store；画 `<td>` 的是 table-body |
| `width` 和 `min-width` 差不多 | ❌ `width` 固定死；`min-width` 是"保底 + 参与剩余空间按比例分配" |
| 不写 `min-width` 就没有最小宽度 | ❌ 默认 **80**（`render-helper.mjs:41`） |
| 列宽可以写百分比 | ❌ `parseInt("20%")` = 20，**当成 20px**。表格列宽不支持百分比 |
| `prop` 只能写一层字段名 | ❌ 底层是 lodash `get`，**支持 `prop="user.info.name"` 点路径** |
| 写了 `prop` 又写插槽，两者会叠加 | ❌ 有插槽就只用插槽，`prop` 被忽略（除非插槽只渲染出注释节点） |
| `#default="{ row }"` 里 `$index` 是全局序号 | ❌ 是**当前页**数组下标，翻页后从 0 重新开始 |
| 插槽函数只在有数据时被调用 | ❌ 列组件会**先用 `{ row: {}, $index: -1 }` 探测调用一次**，深层取值要写可选链 |
| `fixed="right"` 只是加了个样式 | ❌ 它会把该列**重排到列数组末尾**，并让表格进入 `isComplex` 渲染模式 |
| `border` 不写 `="true"` 就没传值 | ❌ 无值属性传 `""`，Boolean 类型的 prop 被 Vue 转成 `true` |
| `v-loading` 是 el-table 的 prop | ❌ 是**指令**，来自 ElLoading，往元素上盖遮罩，**任何元素都能用** |

---

## 十、一句话总结

> `<el-table :data>` 说"有哪些行"，`<el-table-column>` 说"有哪些列"——但**列组件不画列**：它在 `onMounted` 时把自己揉成一份配置 `commit` 进父表格的 store，真正画 `<td>` 的是 table-body。它是**声明**，不是控件。
> 列上的字段分两类——**取值类**（`prop` 决定从 row 的哪个字段取、`label` 是表头文字）和**排版类**（`width` 固定死、`min-width` 保底并按比例分剩余空间、`show-overflow-tooltip` 单行截断加悬浮全文、`fixed` 钉住不随横向滚动并触发列重排）。
> 当一格的内容不是"把字段打印出来"（要放 `el-tag`、要绑 `@click` 的按钮），就用作用域插槽 `#default="{ row }"` 接过这一行数据自己画——**这就是状态列和操作列都不写 `prop` 的原因**。

---

## 十一、往下可以再挖的

- **排序 = 又一个受控组件**：`sortable` + `@sort-change`。⚠️ **后端分页时必须用 `sortable="custom"`**，否则 EP 只对当前页那 10 条排序，看起来完全正确、实际是错的。这是分页 + 排序最经典的坑，配合 `受控组件与el-pagination.md` 一起看。
- **多选**：`type="selection"` + `row-key` + `reserve-selection`（翻页保留选中）。P5 待办批量处理会用到。
- **`formatter` vs 插槽**：只是格式化文本（时间戳 → 日期）用 `:formatter`，要渲染组件才用插槽。别一上来就写插槽。
- **`#header` 插槽**：表头里加提示图标、筛选按钮。
- **配置型子组件在别处的复现**：`<el-option>`（el-select）、`<el-tab-pane>`（el-tabs）、`<el-step>`、`<el-descriptions-item>`——**全是"注册进父组件的配置声明"**。认出模式后，这些组件都不用单独读文档，只要问一句"它把什么 commit 给了父组件"。
- **P6 表单设计器**：设计器要**自己写**这种父子契约（`provide/inject` + 子组件注册），本篇是那时的地基——和 `受控组件与el-pagination.md` 一起构成两块基石。
- **`el-table-v2`**：数据上千行时的虚拟滚动版本，API 完全不同（回到了数组配置），到时再看。
