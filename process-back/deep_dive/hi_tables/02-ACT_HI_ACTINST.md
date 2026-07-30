# 02 · ACT_HI_ACTINST —— 活动轨迹

> 先读 `00-历史表族-宏观.md`（双写模型、八表全景、删除三层次），`01` 篇讲过它与 `ACT_HI_TASKINST` 的分工。
>
> 标本：
> - **test-0004** `175ffafb-84bc-11f1-b2ab-5eea1d7fcc1d`（已办结，**5 行**）
> - **test-0005** `6a897d3d-84d2-11f1-b2ab-5eea1d7fcc1d`（在途，**3 行**）

---

## 一、一句话定位

> **`ACT_HI_ACTINST` 记录"引擎走过的每一步"——流程图上每经过一个元素就一行，包括连线。**

`ACT_HI_TASKINST` 是**以人为中心**（谁办了什么），这张表是**以流程图为中心**（引擎的脚印落在哪些元素上）。它是四张核心表里**行数最多、粒度最细**的一张。

---

## 二、诞生背景：为什么要逐步记录

流程引擎的本质是「按图执行」。图是静态的（`ACT_RE_PROCDEF` 里那份 BPMN），执行是动态的。问题来了：**执行完之后，怎么知道它究竟走了哪条路？**

对于你现在的 leave 流程（一条直线）这个问题很无聊——闭着眼也知道走的是 `startEvent → managerApprove → endEvent`。但真实流程有分支：

```
                ┌─ days ≤ 3 ─► 经理审批 ─┐
提交 ─► 网关 ─┤                          ├─► 结束
                └─ days > 3 ─► 总监审批 ─┘
```

这时"走了哪条路"就不是废话了。而且分支条件依赖运行时变量，**同一份流程定义，不同实例走的路可能完全不同**。光有定义和结果，推不出中间过程。

于是引擎必须**把脚印留下来**。`ACT_HI_ACTINST` 就是那串脚印。

### 为什么连线也要记

这是最反直觉的一点。你的 test-0004 有 5 行，其中 2 行是 `sequenceFlow`：

```
startEvent       员工发起    startEvent      ← 节点
flow1            (空)        sequenceFlow    ← 连线
managerApprove   经理审批    userTask        ← 节点
flow2            (空)        sequenceFlow    ← 连线
endEvent         结束        endEvent        ← 节点
```

只记节点不够吗？**在有分支的图里不够。**

想象一个网关有三条出边，都指向同一个汇聚节点。只记节点的话，轨迹是「网关 → 汇聚节点」，你**无法知道走的是哪条边**。而边上往往写着条件（`${days > 3}`），这恰恰是最需要追溯的信息——"为什么这单走了总监审批？"答案就在那条边上。

再者，前端画流程图时要把走过的路径标绿，**标绿的是线，不是点**。没有连线记录就没法高亮路径。

> 所以连线进轨迹不是设计冗余，是**图的完整性要求**：一条路径 = 点和边交替出现的序列，缺了边就不是路径了。

---

## 三、孪生表：`ACT_RU_ACTINST`

Day 13 的日志暴露了一张我们之前的"四表模型"漏掉的表：

```
o.f.e.i.p.e.A.updateActivityInstance      : update ACT_RU_ACTINST SET ... ASSIGNEE_ = 2 where ID_ = 1761cec3-…
e.i.p.e.H.updateHistoricActivityInstance  : update ACT_HI_ACTINST SET ... ASSIGNEE_ = 2 where ID_ = 1761cec3-…
```

两条 SQL **紧挨着出现、改的是同一个 `ID_`、set 的是同一批字段**。这就是 `00` 篇讲的"双写"在日志里最直白的样子——运行时一份、历史一份，同步维护。

| | `ACT_RU_ACTINST` | `ACT_HI_ACTINST` |
|---|---|---|
| 装什么 | 在途实例的活动记录 | 全部（含在途） |
| 实例完结时 | **删除**（日志里 `delete from ACT_RU_ACTINST … Updates: 3`） | **保留** |
| 谁用 | 引擎内部（判断当前活动、多实例计数等） | 你的 `activities()` 接口 |

**为什么运行时也要单独存一份**：引擎在流转时需要频繁查"当前有哪些活动正在进行"（尤其并行网关、多实例场景要计数），去历史表里翻会越翻越慢——又是一次冷热分离，和 `00` 篇讲的整体思路完全一致。

> 所以运行时表实际是**五张**：EXECUTION / TASK / VARIABLE / IDENTITYLINK / **ACTINST**。之前深挖四表时漏了它，因为发起时它不显眼，办理时才在日志里跳出来。

---

## 四、功能结构：字段分组

### 组 1 · 身份：这是哪一步

| 字段 | test-0004 里的值 | 说明 |
|---|---|---|
| `ID_` | `1761cec3-…`（managerApprove 那行） | **自己独立的 id**，与任务 id 无关 |
| `ACT_ID_` | `managerApprove` / `flow1` | **BPMN 里的元素 id**，最常用 |
| `ACT_NAME_` | `经理审批` / **空** | 元素显示名。**连线通常没有名字 → 这里是空** |
| `ACT_TYPE_` | `userTask` / `sequenceFlow` / `startEvent` / `endEvent` | **元素类型**，过滤的关键 |

⚠️ **`ID_` 与 `ACT_HI_TASKINST.ID_` 不同**，这是和 `01` 篇的重要对比：

```
ACT_HI_TASKINST.ID_  = 1764dc04-…   ← 任务的 id（也是 ACT_RU_TASK.ID_）
ACT_HI_ACTINST.ID_   = 1761cec3-…   ← 活动记录自己的 id
ACT_HI_ACTINST.TASK_ID_ = 1764dc04-… ← 用这个字段指回任务
```

任务和活动是**两个独立对象**（`01` 篇讲过原因：会签一个节点多个任务、`newTask()` 无节点任务），所以各有主键，靠 `TASK_ID_` 关联。

### 组 2 · 归属

| 字段 | 说明 |
|---|---|
| `PROC_INST_ID_` | 属于哪条实例 —— 查轨迹的主键 |
| `EXECUTION_ID_` | 哪个执行游标走的（并行分支时能区分是哪个分支） |
| `PROC_DEF_ID_` | 流程定义 |
| `TASK_ID_` | 若是 userTask，指向 `ACT_HI_TASKINST`；其余类型为空 |
| `CALL_PROC_INST_ID_` | 若是 callActivity（子流程调用），指向被调起的子流程实例 |

`CALL_PROC_INST_ID_` 值得留意：将来做**子流程**时，主流程轨迹里那一行会通过它挂上子流程的完整轨迹，形成树状追溯。你现在用不到，但知道这个字段存在，做子流程时就不会另造轮子。

### 组 3 · 人

| 字段 | 说明 |
|---|---|
| `ASSIGNEE_` | **只有 userTask 才有值**，你的数据里只有 `managerApprove` 是 `2` |

这条在 Day 13 已经验过了：startEvent / endEvent / 两条 sequenceFlow 的 `ASSIGNEE_` **全是空**——自动节点和连线是引擎自己走的，没有"办理人"这个概念。

**这正是「我的已审批」查 `ACT_HI_TASKINST` 而不是这张表的原因**：这里只有一个孤零零的 `ASSIGNEE_`，没有 `CLAIM_TIME_`、`OWNER_`、`PRIORITY_`、`DUE_DATE_`，做不了任务级审计。

### 组 4 · 时间与顺序

| 字段 | 说明 |
|---|---|
| `START_TIME_` | 进入这个元素的时刻 |
| `END_TIME_` | 离开的时刻。**为空 = 当前正停在这里** |
| `DURATION_` | 停留毫秒数（冗余存储，同 `01` 篇的理由） |
| `TRANSACTION_ORDER_` | **同一事务内的执行序号**（下一节详解） |

`END_TIME_` 为空是本表最有用的信号。对比两条标本：

**test-0004（已办结）—— 5 行全有 `END_TIME_`**
```
startEvent      12:24:40.613 → 12:24:40.617   （4ms，瞬间通过）
flow1           12:24:40.620 → 12:24:40.620   （0ms）
managerApprove  12:24:40.620 → 14:48:30.403   （2h23m，等人）
flow2           14:48:30.503 → 14:48:30.503   （0ms）
endEvent        14:48:30.617 → 14:48:30.617   （0ms）
```

**test-0005（在途）—— 3 行，最后一行 `END_TIME_` 为空**
```
startEvent      15:04:29.060 → 15:04:29.060
flow1           15:04:29.060 → 15:04:29.060
managerApprove  15:04:29.060 → (空)            ← 当前停在这里
```

**前端画流程图时，"高亮哪个节点表示当前位置"就是找 `END_TIME_ IS NULL` 的那些行。** P5 做 bpmn-js 高亮时会直接用到。

还能一眼看出**流程的时间分布**：自动元素全是 0~4ms，唯一耗时的是等人的 `managerApprove`。这是流程瓶颈分析的原始素材——**瓶颈永远在人工节点上**，这句话在数据上是可证的。

### 组 5 · 其他

| 字段 | 说明 |
|---|---|
| `DELETE_REASON_` | 非正常结束原因（实例被终止时，未走完的活动会有值） |
| `TENANT_ID_` | 多租户，当前未用 |

---

## 五、⚠️ 重大发现：时间戳会撞车，`START_TIME_` 排序不可靠

这是从你的真实数据里看出来的，**直接影响 Day 14 的 `activities()` 实现**。

### 现象

看 test-0005 的三行：

```
startEvent       2026-07-21 15:04:29.060
flow1            2026-07-21 15:04:29.060
managerApprove   2026-07-21 15:04:29.060
```

**三行的 `START_TIME_` 一模一样，精确到毫秒。**

test-0004 也有：`flow1` 和 `managerApprove` 都是 `12:24:40.620`。

原因很直白：从 startEvent 出发、穿过 flow1、停在 managerApprove，这**整个过程在一个事务里同步跑完**，耗时不到 1 毫秒。数据库时间戳的精度不够分辨它们的先后。

### 后果

你现在的实现：

```java
historyService.createHistoricActivityInstanceQuery()
        .processInstanceId(instanceId)
        .orderByHistoricActivityInstanceStartTime().asc()   // ← 三行的值相同
        .list();
```

**当排序键相同时，SQL 不保证返回顺序**。这意味着轨迹可能给出：

```
flow1 → managerApprove → startEvent      ← 顺序错乱，但没有任何报错
```

而且它**不稳定**——同一条 SQL 在不同时刻、换个数据库、加个索引，顺序都可能变。这类 bug 最难查，因为大多数时候它碰巧是对的。

> 你昨天看到的顺序正确，只是运气好（多半是主键或插入顺序恰好一致）。

### 引擎给的解法：`TRANSACTION_ORDER_`

Flowable 早就知道这个问题，所以有这一列。你的办理日志里能看到它在工作：

```
bulkInsertHistoricActivityInstance:
  flow2      … TRANSACTION_ORDER_ = 1
  endEvent   … TRANSACTION_ORDER_ = 2
```

同一个事务里插入的多行，用递增序号标出真实先后。**排序键应该是 `(START_TIME_, TRANSACTION_ORDER_)` 而不是单独的 `START_TIME_`。**

### 但是：查询 API 不支持按它排序

我查了 `flowable-engine-7.1.0.jar`：

```java
// HistoricActivityInstance（结果对象）—— 有这个 getter
public abstract Integer getTransactionOrder();

// HistoricActivityInstanceQuery（查询器）—— 排序方法只有这些，没有 transactionOrder
orderByHistoricActivityInstanceId / ProcessInstanceId / ExecutionId
orderByActivityId / ActivityName / ActivityType
orderByHistoricActivityInstanceStartTime / EndTime / Duration
orderByProcessDefinitionId / TenantId
```

**字段能读到，但没法让数据库按它排。** 所以只能在 Java 侧二次排序：

```java
list.stream()
    .sorted(Comparator
        .comparing(HistoricActivityInstance::getStartTime)
        .thenComparing(HistoricActivityInstance::getTransactionOrder,
                       Comparator.nullsLast(Comparator.naturalOrder())))
    .map(ActivityTraceVO::of)
    .toList();
```

`nullsLast` 是必要的——老数据或某些路径下 `TRANSACTION_ORDER_` 可能为 null，不处理会 NPE。

轨迹通常几十行以内，内存排序的开销可以忽略。**这个改动建议在 Day 14 落地时一起做**，已登记进排期。

---

## 六、连线要不要过滤（Day 14 待决策）

`ACT_NAME_` 为空的两条 `sequenceFlow` 直接返给前端，轨迹列表会出现两行空白。三个选项：

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| ① 后端过滤 | `activities()` 里剔除 `sequenceFlow` | 列表干净，调用方无脑用 | P5 做路径高亮时拿不到连线，得改回来或另开接口 |
| ② 前端过滤 | 后端全返，前端 `filter(a => a.activityType !== 'sequenceFlow')` | 一份数据两用；后端如实反映引擎行为 | 每个消费方都要记得过滤 |
| ③ 加参数 | `?includeFlows=false` 默认过滤 | 两边兼顾 | 接口多一个参数 |

**倾向 ②**。理由：这张表的语义就是"引擎走过的每一步"，后端擅自删掉一半是在撒谎；而 `ActivityTraceVO` 已经有 `activityType` 字段，前端过滤就一行；P5 的路径高亮**一定**会用到连线（要标绿的正是线）。

> 如果选 ①，记得在 P5 开工时回头看这里——那时候你会需要连线，而接口已经把它扔了。

---

## 七、能不能删

### 层次 1 · DROP 表 → ❌ 不行
同 `00` 篇：schema 校验失败或自动重建。

### 层次 2 · 不写入 → ⚠️ 可以，但代价比 TASKINST 更大

`ACT_HI_ACTINST` 在 **`activity` 级别**就开始写入——**比 `ACT_HI_TASKINST`（需要 `audit`）更低一档**。这意味着：

- 把 `history-level` 调到 `activity`：TASKINST 停写，**ACTINST 照常写**（轨迹还在，「我的已审批」没了）
- 调到 `none`：两张都停写，**所有历史功能全灭**

所以想省写入量，`activity` 是一个"保留轨迹、放弃任务审计"的中间档。但对审批系统来说，「我的已审批」通常比轨迹更刚需，这个档位反而少见。

**关掉后失去什么**：
- 流程轨迹接口（`GET /history/instance/{id}/activities`）
- 前端流程图的"走过路径高亮"和"当前位置高亮"
- 节点级瓶颈分析（哪一步最耗时）
- **分支追溯**——最要命的一条：走了哪条路彻底无从查证

### 层次 3 · 删数据 → ✅ 可以

同 `01` 篇：粒度是**实例**（`deleteHistoricProcessInstance` 连带清四张核心表），或被 `deleteDeployment(id, true)` 级联抹除（你 Day 12 步骤 5 见过）。

---

## 八、实际应用场景

### 场景 1 · 流程轨迹时间线（你正在做的）

```java
historyService.createHistoricActivityInstanceQuery()
        .processInstanceId(instanceId)
        .orderByHistoricActivityInstanceStartTime().asc()
```

配合前端渲染成时间轴。**在途实例也能查**（`00` 篇的双写模型），这是它比"只查完结数据"更实用的地方。

### 场景 2 · BPMN 图高亮（P5 会用）

bpmn-js 渲染流程图后，用这张表的数据上色：

| 数据 | 高亮效果 |
|---|---|
| `END_TIME_` 有值的节点 | 灰色/绿色 = 已走过 |
| `END_TIME_` 为空的节点 | **红色/闪烁 = 当前停留** |
| `ACT_TYPE_='sequenceFlow'` 的 `ACT_ID_` | **绿色加粗 = 走过的路径** |

最后一行就是"必须保留连线"的硬需求。前端拿到的 `flow1`/`flow2` 直接就是 bpmn-js 里的元素 id，`canvas.addMarker('flow1', 'highlight')` 即可。

### 场景 3 · 瓶颈分析

```sql
SELECT ACT_ID_, ACT_NAME_, AVG(DURATION_) AS avg_ms, COUNT(*) AS cnt
FROM ACT_HI_ACTINST
WHERE ACT_TYPE_ = 'userTask' AND END_TIME_ IS NOT NULL
GROUP BY ACT_ID_, ACT_NAME_
ORDER BY avg_ms DESC;
```

找出"哪个审批环节最拖"。和 `ACT_HI_TASKINST` 的区别：那张表按**人**统计（谁批得慢），这张表按**节点**统计（哪一环慢）。两个视角回答不同问题。

### 场景 4 · 分支追溯与流程挖掘

"为什么这单没走总监审批" → 查轨迹里有没有那个 `ACT_ID_`，以及走的是哪条 `sequenceFlow`。

规模大了以后，这张表就是**流程挖掘（Process Mining）**的原始日志：把成千上万条实例的轨迹聚合，能算出真实路径分布（"85% 走了简易审批"）、发现设计时没预料到的路径、找出从没被走过的死节点。这是把 BPM 系统从"执行工具"变成"分析资产"的基础，而全部素材就来自这一张表。

---

## 九、踩坑清单

| # | 坑 | 后果 | 对策 |
|---|---|---|---|
| 1 | **只按 `START_TIME_` 排序** | 同毫秒的行顺序随机，轨迹错乱且不报错 | Java 侧再按 `TRANSACTION_ORDER_` 二次排序 |
| 2 | 忘了过滤 `sequenceFlow` | 列表出现空白行（`ACT_NAME_` 为空） | 见第六节的三选一 |
| 3 | 用这张表做「我的已审批」 | 缺 CLAIM_TIME_/OWNER_ 等字段，还要手动过滤类型 | 人工任务归 `ACT_HI_TASKINST` |
| 4 | 把 `ID_` 当 taskId 用 | 查不到任务 | 用 `TASK_ID_` 字段 |
| 5 | 以为在途实例查不到轨迹 | 白做"仅完结可查"的限制 | 双写模型下在途照样有，只是末行 `END_TIME_` 为空 |
| 6 | 以为 `ASSIGNEE_` 每行都有 | 拿到一堆 null | 只有 userTask 才有 |
| 7 | 认为连线记录是冗余，顺手删了 | P5 路径高亮做不了、分支无从追溯 | 见第二节 |

---

## 十、和你项目的连接点

| 位置 | 关系 |
|---|---|
| `FlowableHistoryServiceImpl.activities()` | 唯一直接查这张表的地方 |
| `ActivityTraceVO` | 字段投影，已含 `activityType`（前端过滤要用） |
| Day 14 待决策项 | ① `sequenceFlow` 过滤方案；② **`TRANSACTION_ORDER_` 二次排序（本篇新增）** |
| Day 18「历史页」 | 时间轴消费方 |
| P5 BPMN 设计器 | 路径高亮 + 当前位置高亮的数据源 |

**两条标本对照速查**：

```
test-0004（办结，5 行）  startEvent → flow1 → managerApprove → flow2 → endEvent
                         END_TIME_ 全部有值；仅 managerApprove 有 ASSIGNEE_=2
                         耗时：自动元素 0~4ms，managerApprove 2h23m

test-0005（在途，3 行）  startEvent → flow1 → managerApprove
                         managerApprove 的 END_TIME_ 为空 ← 当前位置
                         三行 START_TIME_ 全为 15:04:29.060 ← 排序撞车的活样本
```
