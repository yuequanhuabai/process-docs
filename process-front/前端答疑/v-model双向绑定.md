# v-model 双向绑定（答疑笔记）

> 由答疑 CLI 整理。通用前端原理。触发点：`<el-switch v-model="latestOnly" />` 是什么意思。
> 关联：`props向下events向上.md`（v-model 是它的语法糖）、`change事件.md`（同一控件上常与 v-model 并存）。

## 一句话定义

> `v-model` = 变量和表单控件的**双向绑定**——把一个变量和一个控件"焊在一起"，两边自动同步。

## 本项目例子

```ts
const latestOnly = ref(false)          // script 里的变量
```
```html
<el-switch v-model="latestOnly" />     // template 里的开关
```

建立两条自动同步：
1. **变量 → 界面**：`latestOnly` 是 false，开关显示"关"；代码改成 true，开关自动变"开"。
2. **界面 → 变量**：用户拨动开关，`latestOnly` 自动跟着变，不用手写代码去读开关状态再赋值。

**双向**就体现在：谁变了，另一边自动跟上。

## 为什么需要它（本质）

默认数据绑定是**单向**的：数据 → 界面（`data → view`）。这对"只显示"的东西够用（表格文字）。
但**表单控件**（输入框/开关/下拉）要跟用户交互，还需要反方向：用户操作 → 数据更新（`view → data`）。

没有 v-model 时要手写：
```html
<el-switch
  :model-value="latestOnly"                      // 变量→界面
  @update:model-value="v => latestOnly = v"      // 界面→变量，手动回写
/>
```
`v-model` 就是**这两行的语法糖**——一个写法自动展开成"绑值 + 监听变化回写"。本质不是新魔法，是省掉手动同步的简写。

> 后端类比：像把一个字段和一个 UI 控件做了数据绑定，两者始终是一份、自动一致，省掉手写 getter/setter 来回搬。

## 易混点：v-model vs @change

```html
<el-switch v-model="latestOnly" @change="handleLatestChange" />
```

| | 作用 |
|---|---|
| `v-model="latestOnly"` | **同步值**——把开关状态存进 latestOnly（管"是什么"） |
| `@change="handleLatestChange"` | **触发副作用**——值变了之后要顺带干的事（回第一页 + 重查列表，管"变了之后做什么"） |

v-model 只管把值同步好；值变了要不要触发查询，是 @change 干的活。详见 `change事件.md`。

## 一句话总结

> `v-model` = 变量和控件的**双向绑定**，本质是 `:绑值 + @监听回写` 的语法糖，让"用户操作"和"数据变化"自动一致，省掉手动同步代码。底层仍严格遵守单向数据流（见 `props向下events向上.md`）。
