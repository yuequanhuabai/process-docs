# 受控组件 与 el-pagination 逐字段拆解（答疑笔记）

> 由答疑 CLI 整理。触发点：`views/process/index.vue:39-46` 那段 `<el-pagination>`，每个字段什么意思、值分别代表什么？
> 前置：`模板语法-冒号与@.md`（`:` 和 `@` 是什么）。关联：`props向下events向上.md`、`v-model双向绑定.md`、`change事件.md`。
> 环境：Vue 3.5.39 / Element Plus 2.14.2。下文所有源码行号指
> `process-front/node_modules/element-plus/es/components/pagination/src/pagination.mjs`（**升级 EP 版本后行号可能变，认代码不认行号**）。

本篇的可复用知识其实是**受控组件**这个模式——`el-table` 的排序、`el-form` 的校验、P6 表单设计器全是同一套。`el-pagination` 只是第一个撞上它的实例。

---

## 一、先把这一堆写法分成三类

```html
<el-pagination
    class="pager"                          ← ① 静态属性（字符串）
    layout="total, prev, pager, next"      ← ① 也是静态字符串！最容易误会的一个
    :total="total"                         ← ② v-bind：传 JS 变量的值
    :current-page="current"                ← ②
    :page-size="size"                      ← ②
    @current-change="handlePageChange"     ← ③ v-on：订阅事件
/>
```

`layout` **没有冒号**，所以传的就是 `"total, prev, pager, next"` 这一整个字符串——**它不是四个属性，是一个逗号分隔的"配方"**。而 `:total` 有冒号，传的是变量 `total` 里那个数字。详见 `模板语法-冒号与@.md`。

---

## 二、逐个字段

### `layout` —— 装配清单

组件内部 `props.layout.split(',').map(item => item.trim())`（`pagination.mjs:322`），再按顺序去一张 `TEMPLATE_MAP` 里取部件拼起来（`pagination.mjs:286-320`）。可用槽位一共 8 个：

| 值 | 渲染出什么 |
|---|---|
| `total` | 「共 23 条」那行字 |
| `prev` | 上一页箭头 |
| `pager` | 页码按钮 `1 2 3` |
| `next` | 下一页箭头 |
| `jumper` | 「前往 __ 页」跳页输入框 |
| `sizes` | 「10 条/页」下拉，让用户改每页条数 |
| `slot` | 你自己塞的自定义内容 |
| `->` | **分隔符**，它后面的部件靠右对齐（`pagination.mjs:326`） |

**顺序即显示顺序。** 我们写的 `total, prev, pager, next` = 总条数最左，然后上一页、页码、下一页；**没有跳页框、没有每页条数选择器**。

组件默认值是 `"prev, pager, next, jumper, -> , total"`（`pagination.mjs:65-74`）——页码在左、总数被 `->` 推到最右。我们这行是显式覆盖成了另一种排布。

> 写错槽位名（比如 `pagerr`）不会报错，`TEMPLATE_MAP[c]` 取到 `undefined` 就那么塞进去了，表现为少一个部件或渲染异常。**拼写要小心。**

### `:total` —— 总条数（数据总量，不是页数）

值来自后端：`loadList()` 里 `total.value = page.total`（`views/process/index.vue:79`），`page.total` 就是后端 `IPage` 的 `total`。

**组件靠它算页数**（`pagination.mjs:221`，源码原文）：

```js
pageCount = Math.max(1, Math.ceil(props.total / pageSizeBridge.value))
```

`total=23`、`page-size=10` → `ceil(2.3)` = **3 页**，页码区渲染 `1 2 3`。

> **这解释了 Day 1 为什么坚持后端返回 `R<IPage<T>>` 而不是 `R<List<T>>`**：没有 `total`，前端根本算不出该画几个页码。前后端契约 `PageResult<T>`（`src/api/user.ts:3`）对齐的也正是这几个字段。

### `:current-page` —— 当前第几页（从 1 开始）

`1` 表示第一页。**1-based**——MyBatis-Plus 的 `Page` 也是 1-based，所以 `pageDefinitions(current.value, ...)` 直接传，不用换算。

> 横向对照：Spring Data 的 `Pageable` 是 **0-based**（第一页是 0）。若后端改用 Spring Data 分页，这里必须 `current - 1`，否则永远差一页——分页联调最经典的 off-by-one。

### `:page-size` —— 每页几条

本页恒为 `10`（`size = ref(10)`，`index.vue:69`）。因为 `layout` 里没有 `sizes` 部件、用户改不了它，所以**不需要**监听 `size-change`。（想加 `sizes` 时必须补，见第六节坑 3。）

### `@current-change` —— 用户翻页时它喊你

组件把新页码作为参数发出，`handlePageChange(p)` 接住（`index.vue:125-128`）：

```ts
function handlePageChange(p: number) {
  current.value = p    // 记下新页码
  loadList()           // 重新查
}
```

组件一共能发 7 个事件（`pagination.d.ts:42-50`）：`current-change`、`size-change`、`change`、`update:current-page`、`update:page-size`、`prev-click`、`next-click`。我们只订阅了第一个。

---

## 三、机制：值是怎么流动的

**整个组件最该理解的一点：它自己不存页码。**

源码 `pagination.mjs:223-238` 的 `currentPageBridge`：

```js
get() { return isAbsent(props.currentPage) ? innerCurrentPage.value : props.currentPage }
                                              //  你传了就用你的 ↑
set(v) {
  let newCurrentPage = v
  if (v < 1) newCurrentPage = 1
  else if (v > pageCountBridge.value) newCurrentPage = pageCountBridge.value   // 夹进合法范围
  ...
  emit('update:current-page', newCurrentPage)
  emit('current-change', newCurrentPage)      // 只是喊一声，不自己改
}
```

- **读**：优先读你传进来的 prop；
- **写**：不改 prop（props 只读），只 `emit` 事件。

完整闭环：

```
你点「第 2 页」
   ↓
组件 emit('current-change', 2)                      ← 它只负责喊
   ↓
handlePageChange(2) → current.value = 2 → loadList()  ← 你负责改和查
   ↓
current 变了 → :current-page 传进去的新值 = 2 → 页码高亮跳到 2
```

**数据的"家"在你的组件里（`current` ref），分页器只是显示器 + 喇叭。** 这正是 `props向下events向上.md` 那条单向数据流的实例。

---

## 四、诞生背景：为什么它不自己管

**旧世界（jQuery 分页插件）是自管状态的**：插件内部存着 `currentPage`，你给它一个 URL，它自己发 ajax、自己刷新表格。

**痛点：**

1. **状态有两份**——插件内部一份、页面里一份，迟早不同步；
2. **联动做不了**——比如切「只看最新版本」开关要**回到第一页**，可页码在插件肚子里，你改不动它。我们 `handleLatestChange` 里那句 `current.value = 1`（`index.vue:131-134`），在旧模式下是写不出来的；
3. **改行为得改插件**——想加筛选条件、换请求头、改错误提示，只能去动插件源码。

**新方案（受控组件）**：状态只留一份、住在你手里；组件退化成"显示 + 喊一声"。副作用（发请求）也归你，于是任何联动都能自然写。

**代价**：你得自己接线——三个 props 一个事件，忘一个就不动。

**Element Plus 把这个态度写死在了源码里**（`pagination.mjs:189-201` 的 `assertValidUsage` + `276-280`）：

```js
if (isAbsent(props.total) && isAbsent(props.pageCount)) return false          // 两个都没给
if (!isAbsent(props.currentPage) && !hasCurrentPageListener) return false     // 给了 currentPage 却不监听
...
if (!assertValidUsage.value) { debugWarn(...); return null }                  // 整个组件不渲染
```

**传了 `:current-page` 却不监听 `current-change`，分页器会直接消失**（不是不动，是整个不渲染）+ 控制台警告。翻译成人话：**"要么完全别管，要么管到底，不许半管。"**

顺带：**非受控模式**也在（`pagination.mjs:204-205`）——改用 `default-current-page` / `default-page-size`，不传 `current-page`，组件就用内部的 `innerCurrentPage` 自己存。EP 两种模式都支持，我们选的是受控。

> **为什么不用 `v-model:current-page`？** 事件表里有 `update:current-page`，说明它支持。但 `v-model` 只把新页码同步进变量，**不会触发重新查询**，还得再配个 `watch`。用 `@current-change` 一步到位——同一个取舍在 `change事件.md` 里讨论过（`@change` vs `watch`）。

---

## 五、动手实验（改一行看效果，看完改回来）

**实验 1 · 感受 `layout` 是配方**
临时改成 `"total, sizes, prev, pager, next, jumper"` → 多出「10 条/页」下拉和「前往 __ 页」输入框。再改成 `"prev, pager, next, ->, total"` → 总条数被推到最右。

**实验 2 · 验证"半管会罢工"**
删掉 `@current-change="handlePageChange"` 整行 → **分页器整个消失**，控制台一条警告。这就是 `assertValidUsage` 在起作用。

**实验 3 · 验证 `sizes` 的强制要求**
在实验 1 基础上（layout 含 `sizes`）不加 `@size-change` → 分页器同样消失（`pagination.mjs:191-199`）。

---

## 六、回到本项目：三处值得注意

**1. `class="pager"` 目前是空钩子。**
`views/process/index.vue` 从头到尾**没有 `<style>` 块**（文件到 136 行 `</script>` 就结束了），所以 `.pager` / `.process-page` / `.toolbar` 三个 class 都没有任何样式，分页器会紧贴表格、不居右。参考样式在 `process_manage/03-完整代码.md:192-212`。

**2. 删除时的页码越界，我们的处理比组件更早。**
`handleDelete` 里（`index.vue:116-118`）：

```ts
if (list.value.length === 1 && current.value > 1) current.value -= 1
```

组件内部其实也有兜底（`pagination.mjs:239-241`）：

```js
watch(pageCountBridge, (val) => {
  if (currentPageBridge.value > val) currentPageBridge.value = val   // 会再 emit 一次
})
```

但它是**事后**修正：先查到空页 → `total` 变小 → 页数变少 → 夹回去 → emit `current-change` → **又触发一次 `loadList()`**，多一次请求 + 一次空表格闪烁。手动提前减一把这次往返省掉了，是对的。

**3. 将来加 `sizes` 时的连带改动**：`layout` 里加 `sizes` → 必须同时加 `@size-change="handleSizeChange"`，在其中 `size.value = newSize` 并 `loadList()`，否则组件不渲染（坑同实验 3）。可选条数默认是 `[10, 20, 30, 40, 50, 100]`（`pagination.d.ts:15`），用 `:page-sizes` 覆盖。

---

## 七、常见误解速查

| 误解 | 实际 |
|---|---|
| `layout` 是四个属性 | ❌ 是**一个字符串**，逗号分隔的装配配方，顺序即显示顺序 |
| `total` 是总页数 | ❌ 是**总条数**；页数由 `ceil(total / pageSize)` 算出 |
| 分页器会自己发请求 | ❌ 它只 emit 事件，请求是你的 `loadList()` 发的 |
| 分页器内部记着当前页 | ❌ 受控模式下读的是你的 prop；它只在你**不传** `current-page` 时才自己存 |
| 组件会直接改我的 `current` 变量 | ❌ props 只读，它只 emit，改的动作是你 handler 里写的 |
| 不监听 `current-change` 只是翻页失效 | ❌ **整个分页器不渲染**（`assertValidUsage` 返回 null） |

---

## 八、一句话总结

> `layout` 是**装配配方**（字符串、逗号分隔、顺序即显示顺序）；`total` / `current-page` / `page-size` 是**喂给它的三个数字**（用 `ceil(total/pageSize)` 算页数、用 `current-page` 决定高亮谁）；`@current-change` 是它**唯一的输出**——用户点了哪一页。
> 它**不存状态、不发请求**：状态住在你的 `current` ref 里，请求由 `loadList()` 发。这就是**受控组件**——换来了完全的联动自由，代价是三个 props 一个事件必须接全，少接一个就罢工不渲染。

---

## 九、往下可以再挖的

- **受控模式在别处的复现**：`el-table` 的 `:sort-order` + `@sort-change`、`el-dialog` 的 `v-model` 开关、`el-form` 的校验触发——认出模式后，这些组件的文档几乎不用读，直接找"它 emit 什么"即可。
- **P6 表单设计器**：设计器里每个字段组件都要自己实现这套契约（`modelValue` in / `update:modelValue` out），到时会从"使用受控组件"变成"编写受控组件"，本篇是那时的地基。
- **`pageCount` 直传模式**：不传 `total` 而直接传 `pageCount`（`pagination.mjs:220`），适用于后端只给页数不给总数的接口。
