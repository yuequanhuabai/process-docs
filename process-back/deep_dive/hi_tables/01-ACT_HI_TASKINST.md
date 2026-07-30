# 01 · ACT_HI_TASKINST —— 人工任务历史

> 先读 `00-历史表族-宏观.md`（双写模型、八表全景、删除三层次）。
>
> 标本：**test-0004**（已办结）`175ffafb-84bc-11f1-b2ab-5eea1d7fcc1d`，任务行 `1764dc04-84bc-11f1-b2ab-5eea1d7fcc1d`。

---

## 一、一句话定位

> **`ACT_HI_TASKINST` 记录"每一个需要人来办的任务，从生成到办结的全过程"——一个 userTask 一行。**

它是四张核心历史表里**唯一以"人"为中心**的表。其余三张记的是引擎的行为（走到哪、带了什么数据），只有它记的是**人的工作**：这活儿派给谁、谁认领了、什么时候办完的、办了多久。

---

## 二、诞生背景：为什么单独给"人工任务"开一张表

引擎已经有 `ACT_HI_ACTINST` 了，它记录走过的**每一个节点**，其中当然包括 userTask。既然如此，为什么还要专门再开一张 `ACT_HI_TASKINST`？

看你库里的真实数据就明白了。test-0004 办结后：

**`ACT_HI_ACTINST`（5 行）**
```
startEvent       员工发起    startEvent      assignee=空
flow1            (空)        sequenceFlow    assignee=空
managerApprove   经理审批    userTask        assignee=2     ← 只有这一行是人办的
flow2            (空)        sequenceFlow    assignee=空
endEvent         结束        endEvent        assignee=空
```

**`ACT_HI_TASKINST`（1 行）**
```
1764dc04-…   经理审批   managerApprove   assignee=2   START 12:24:40.620   END 14:48:29.993   DURATION 8629374
```

差别在三个层面：

### ① 信噪比：5 行里只有 1 行和人有关

「我的已审批」这个功能，本质是问"**我办过哪些事**"。如果去 `ACT_HI_ACTINST` 查，得先按 `ACT_TYPE_='userTask'` 过滤掉连线和自动节点——而这个过滤条件是**业务知识**，不该由每个调用方各自记住。

Flowable 的做法是：**把这层过滤固化成一张表**。`ACT_HI_TASKINST` 里天生只有人工任务，查它不需要任何类型过滤。你的 `approved()` 之所以能写得那么干净：

```java
historyService.createHistoricTaskInstanceQuery()
        .taskAssignee(UserContext.userId())
        .finished()
```

——没有一句 `ACT_TYPE_` 判断，正是这张表已经替你筛过了。

> 这也解释了你昨天遇到的对比：`activities()` 查 `ACT_HI_ACTINST` 就**必须**处理 `sequenceFlow` 的噪音，而 `approved()` 查 `ACT_HI_TASKINST` 就不用。同一个问题在两张表上待遇不同，根源在这里。

### ② 字段维度：任务有一堆节点没有的属性

人工任务是个复杂对象，它有一堆「引擎节点」根本不需要的概念：

| 概念 | 字段 | ACT_HI_ACTINST 有吗 |
|---|---|---|
| 谁拥有（委派场景的原主人） | `OWNER_` | ❌ |
| 什么时候认领的 | `CLAIM_TIME_` | ❌ |
| 优先级 | `PRIORITY_` | ❌ |
| 截止时间 | `DUE_DATE_` | ❌ |
| 绑定的表单 | `FORM_KEY_` | ❌ |
| 任务描述 | `DESCRIPTION_` | ❌ |
| 父任务（子任务场景） | `PARENT_TASK_ID_` | ❌ |
| 分类 | `CATEGORY_` | ❌ |

`ACT_HI_ACTINST` 只有 `ASSIGNEE_` 一个和人相关的字段，因为它的职责是"记录引擎走过的步子"，一个 sequenceFlow 不需要优先级和截止时间。**硬把这些字段塞进 ACTINST，等于让 90% 的行常年存着一堆 NULL。**

### ③ 生命周期：任务和节点不总是一一对应

这一点最隐蔽，但也最能说明为什么必须分表：

- **一个 userTask 节点，可能产生多个任务实例**——比如多实例（会签）节点，一个节点派给 5 个人就是 5 条任务
- **任务可以脱离节点存在**——`taskService.newTask()` 能创建独立任务（不属于任何流程），这类任务在 `ACT_HI_TASKINST` 里有行，在 `ACT_HI_ACTINST` 里**根本没有对应记录**（它压根不在流程图上）
- **子任务**（`PARENT_TASK_ID_`）也是纯任务概念，流程图上没有它

所以两张表不是"一份数据存两遍"，而是**两个不同的领域对象各自的历史**。它们在最常见的"单实例 userTask"场景下恰好一一对应，容易让人误以为冗余。

---

## 三、功能结构：字段分组理解

不要按建表语句的顺序背字段，按**它回答什么问题**分组：

### 组 1 · 身份：这是哪个任务

| 字段 | 说明 |
|---|---|
| `ID_` | 任务 id。**与 `ACT_RU_TASK.ID_` 完全相同** |
| `TASK_DEF_KEY_` | BPMN 里的节点 id，你的是 `managerApprove` |
| `NAME_` | 节点显示名，你的是 `经理审批` |
| `TASK_DEF_ID_` | 任务定义的内部 id（一般用不上） |

**`ID_` 相同这件事非常关键**，是理解双写模型的最好例证：

```
ACT_RU_TASK.ID_    = 1764dc04-84bc-11f1-b2ab-5eea1d7fcc1d   ← 办理前
ACT_HI_TASKINST.ID_= 1764dc04-84bc-11f1-b2ab-5eea1d7fcc1d   ← 办理后（RU 那行已删）
```

同一个任务在两张表里**共用同一个主键**。所以：

- 你 API 里传的 `taskId`，办理前能在 RU 查到，办理后能在 HI 查到，**是同一个 id**
- 这就是 `getTaskOrThrow` 报错文案写成「不存在**或已办理**」的原因——RU 里查不到时，它可能已经躺在 HI 里了，运行时表分不清这两种情况
- 前端拿着一个 taskId，可以先查待办详情，查不到再查历史详情，**不需要换 id**

对比一下 `ACT_HI_ACTINST`：它有**自己独立的 `ID_`**（你日志里的 `1761cec3-…`），另用一个 `TASK_ID_` 字段指回任务。这也侧面说明两张表是各自独立的对象，不是同一份数据的两个副本。

### 组 2 · 归属：属于哪条流程

| 字段 | 你的值 |
|---|---|
| `PROC_INST_ID_` | `175ffafb-…`（test-0004） |
| `PROC_DEF_ID_` | `leaveProcess:1:e531deaa-…` |
| `EXECUTION_ID_` | `17609740-…`（游标行的 id） |

`PROC_INST_ID_` 是最常用的关联键——查"这一单的所有审批记录"就靠它。注意独立任务（`newTask()`）这几个字段全是 NULL。

### 组 3 · 人：谁办的（本表的核心）

| 字段 | 含义 | 你的值 |
|---|---|---|
| `ASSIGNEE_` | **当前/最终办理人** | `2`（manager） |
| `OWNER_` | 委派场景下的原主人 | 空 |
| `CLAIM_TIME_` | 认领时间 | 有值（claim 时写） |

**`ASSIGNEE_` = '2' 就是你昨天反复强调的"命门"。** 它的值来自 `complete()` 里那段：

```java
if (task.getAssignee() == null) {
    taskService.claim(task.getId(), userId);   // ← 就为了写这一个字段
}
taskService.complete(task.getId(), req.getVariables());
```

如果不 claim 直接 complete，任务照样能办掉、流程照样流转，但 `ASSIGNEE_` 会**留空**——历史上就成了一条"没人办过的已办任务"。而「我的已审批」查的正是 `taskAssignee(userId)`，也就是这一列。所以那三行代码不是可有可无的礼貌，是**「我的已审批」这个功能能否存在的唯一前提**。

> `OWNER_` 和 `ASSIGNEE_` 的区别在**委派（delegate）**场景：经理把任务转给助理处理，`OWNER_` 记经理（我才是负责人）、`ASSIGNEE_` 记助理（现在她在办）。助理办完后任务回到经理手上。你现在没用委派，`OWNER_` 一直是空的。

### 组 4 · 时间：什么时候、办了多久

| 字段 | 你的值 | 含义 |
|---|---|---|
| `START_TIME_` | `12:24:40.620` | 任务**生成**时间（不是认领时间） |
| `END_TIME_` | `14:48:29.993` | 办结时间 |
| `DURATION_` | `8629374`（毫秒 ≈ 2h23m） | 冗余存储的耗时 |

三个要点：

**① `END_TIME_` 是"是否办完"的唯一判据。** 在途任务这一列是 NULL。你 `approved()` 里那句 `.finished()` 翻译成 SQL 就是 `END_TIME_ IS NOT NULL`——**去掉它，正等着你办的任务会混进"我的已审批"**。（因为双写模型下，任务一生成 HI 就有行了。）

**② `DURATION_` 是刻意的冗余。** 完全可以用 `END_TIME_ - START_TIME_` 算出来，引擎仍然存一份。原因是报表——"平均审批耗时""超过 24 小时未办的任务"这类统计，直接 `AVG(DURATION_)` / `WHERE DURATION_ > 86400000` 就行，不必在 SQL 里做日期减法（跨数据库方言还不一样）。**这是典型的"用存储空间换查询效率"**。

**③ `START_TIME_` 记的是任务生成时刻，不是有人开始处理的时刻。** 你这条 `DURATION_` 8629374ms（2 小时 23 分）里，绝大部分是"任务躺在待办箱里没人管"的等待时间，不是"经理审批花了 2 小时"。真要区分"等待时长"和"处理时长"，得用 `CLAIM_TIME_` 拆成两段：

```
START_TIME_ ──等待──► CLAIM_TIME_ ──处理──► END_TIME_
```

做流程效率分析时这个区分很重要——"审批慢"到底是**没人看**还是**看了半天定不下来**，优化手段完全不同。

### 组 5 · 结束方式与其他

| 字段 | 说明 |
|---|---|
| `DELETE_REASON_` | 非正常结束的原因。正常办结为 NULL |
| `PRIORITY_` | 优先级，默认 50 |
| `DUE_DATE_` | 截止时间，做超时预警用 |
| `FORM_KEY_` | 绑定的表单标识，你现在是 NULL（P6 才会用上） |
| `CATEGORY_` / `DESCRIPTION_` / `PARENT_TASK_ID_` / `TENANT_ID_` | 分类 / 描述 / 父任务 / 多租户，当前都没用 |

`DELETE_REASON_` 和实例表那个同名字段是一个思路：**正常走完为 NULL，被外力干掉才有值**。实例被终止时，它名下未办的任务也会被撤销，那些任务的 `DELETE_REASON_` 就会有值（如 `deleted`）。

---

## 四、能不能删（三个层次）

按 `00` 篇的框架逐层回答：

### 层次 1 · DROP 表 → ❌ 不行

引擎启动时 schema 校验会失败或自动重建。表结构是引擎契约。

### 层次 2 · 不写入（历史级别调低）→ ⚠️ 可以，但代价明确

`ACT_HI_TASKINST` 在 **`audit` 级别**（Flowable 默认）才写入。把 `flowable.history-level` 调到 `activity`，这张表就不再有新数据。

**引擎照常运转**——流程该发起发起、该流转流转，因为引擎从不读历史表。

**但你会失去**：

| 失去的能力 | 具体表现 |
|---|---|
| 「我的已审批」 | `GET /history/approved` 永远返回空列表 |
| 审批耗时统计 | 没有 `DURATION_` 可算 |
| "这单谁批的"（精确到任务） | 只能退而求其次去 `ACT_HI_ACTINST` 看 `ASSIGNEE_` |
| 任务级审计（认领时间、委派链、优先级） | 全部消失，ACTINST 里没有这些字段 |

**结论：审批类系统不应该关掉它。** 关掉它省的那点写入量，换掉的是这类系统的核心价值。真要优化性能，先考虑 `async-history`（异步写）而不是关掉。

反过来说，如果做的是**纯自动化流程**（服务编排、定时任务链，全程无人工节点），这张表本来就是空的，级别调到 `activity` 完全合理。

### 层次 3 · 删数据（保留表）→ ✅ 可以，且生产必做

三种方式：

```java
// 按实例删（连带清掉该实例在四张核心表里的所有行）
historyService.deleteHistoricProcessInstance(instanceId);

// 按查询批量删
historyService.createHistoricProcessInstanceQuery()
        .finishedBefore(someDate).list()  // 再逐条删
```

以及你已经踩过的：`deleteDeployment(id, true)` 会**连历史一起抹除**。

⚠️ **删除的粒度是"实例"，不是"任务"。** Flowable 不提供"只删某个历史任务、保留实例"的 API——因为那会让历史变得不自洽（实例说走过这个节点，任务记录却没了）。历史数据的完整性是按实例保证的。

**生产建议**：不要删，要**归档**。典型做法是定时把 N 年前的完结实例导出到数仓/冷库，再从引擎库删除。审批记录往往有法定保存期限（劳动争议、财务合规），直接删可能违规。

---

## 五、实际应用场景

### 场景 1 · 「我的已审批」（你正在做的）

```java
historyService.createHistoricTaskInstanceQuery()
        .taskAssignee(UserContext.userId())     // ASSIGNEE_ = 当前用户
        .finished()                             // END_TIME_ IS NOT NULL
        .orderByHistoricTaskInstanceEndTime().desc()
```

**这个功能百分之百建立在这张表上**，没有替代方案。三个条件缺一不可：
- `taskAssignee` 要有值 → 靠 `complete()` 里的自动 claim
- `finished()` → 否则待办会混进来
- 按 `END_TIME_` 倒序 → 最近办的排前面（用 `START_TIME_` 排会按"任务生成时间"排，语义不对）

### 场景 2 · 单据的审批链展示

"这张请假条经过了谁的手"——按 `PROC_INST_ID_` 查这张表，按 `START_TIME_` 升序，就得到完整审批链：

```
张三提交 → 李经理审批（同意，耗时2h23m）→ 王总监审批（同意，耗时10min）
```

比查 `ACT_HI_ACTINST` 干净得多（不用过滤连线和自动节点），而且有耗时。**多级审批流程里这是最常用的查询。**

### 场景 3 · 效率分析与考核

这张表天生是一张**事实表**（每行一个事件 + 度量值 `DURATION_`），非常适合做统计：

| 指标 | SQL 思路 |
|---|---|
| 各审批人平均耗时 | `GROUP BY ASSIGNEE_, AVG(DURATION_)` |
| 各节点平均耗时（找瓶颈） | `GROUP BY TASK_DEF_KEY_, AVG(DURATION_)` |
| 超时未办 | `WHERE END_TIME_ IS NULL AND DUE_DATE_ < NOW()` |
| 积压待办 TOP N | `WHERE END_TIME_ IS NULL GROUP BY ASSIGNEE_` |
| 等待 vs 处理耗时拆分 | `CLAIM_TIME_ - START_TIME_` vs `END_TIME_ - CLAIM_TIME_` |

注意最后一行——**在途任务也在这张表里**（`END_TIME_` 为 NULL），所以"当前积压"和"历史效率"可以用同一张表算，不用联 RU 表。这是双写模型带来的额外便利。

### 场景 4 · 合规审计

"三年前那笔 50 万报销是谁批的" —— `ASSIGNEE_` + `END_TIME_` + `PROC_INST_ID_` 三个字段就能定位。这是审批系统被审计时最常被问的问题，也是**历史表不能随便删**的现实原因。

---

## 六、踩坑清单

| # | 坑 | 后果 | 对策 |
|---|---|---|---|
| 1 | `complete` 前不 claim | `ASSIGNEE_` 为 NULL，「我的已审批」永远查不到 | 你已经处理了（未认领先 claim） |
| 2 | 忘了 `.finished()` | 待办混进已审批列表 | 你已经处理了 |
| 3 | 以为办完任务 id 就失效了 | 白白换 id 或报错 | RU/HI **共用同一个 `ID_`**，办理前后是同一个 taskId |
| 4 | 用 `START_TIME_` 排"最近审批" | 顺序错乱（生成早 ≠ 办得早） | 用 `END_TIME_` 排序 |
| 5 | 把 `DURATION_` 当"审批花了多久" | 实际含大量排队等待时间 | 要精确就用 `CLAIM_TIME_` 拆两段 |
| 6 | 想删单条历史任务 | 没有这个 API | 删除粒度是实例 |
| 7 | 上线后才想开 `full` 级别 | 历史补不回来 | 审计需求要在**上线前**定 |
| 8 | 用 `ACT_HI_ACTINST` 做「我的已审批」 | 要手动过滤类型，且缺 CLAIM_TIME_/OWNER_ 等字段 | 人工任务的事交给 TASKINST |

---

## 七、和你项目的连接点

| 位置 | 关系 |
|---|---|
| `FlowableHistoryServiceImpl.approved()` | 唯一直接查这张表的地方 |
| `FlowableTaskServiceImpl.complete()` 里的 `claim` | **为这张表的 `ASSIGNEE_` 服务**，别当成多余代码删了 |
| `ApprovedTaskVO` | 这张表的字段投影 |
| Day 18「已审批页」 | 前端消费方 |
| Day 31 挂起项「异常状态码粒度」 | 无关，但同属"上线前要定的事" |

**当前库里的这一行，就是上面所有讨论的实体**：

```
ID_          1764dc04-84bc-11f1-b2ab-5eea1d7fcc1d   ← 与 ACT_RU_TASK 那行同 id
NAME_        经理审批
TASK_DEF_KEY_ managerApprove
ASSIGNEE_    2                                       ← 命门
START_TIME_  2026-07-21 12:24:40.620                 ← 任务生成
END_TIME_    2026-07-21 14:48:29.993                 ← 办结
DURATION_    8629374                                 ← 含 2h20m 的排队等待
```
