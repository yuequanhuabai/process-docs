# 04 · ACT_HI_VARINST —— 变量最终值

> 先读 `00-历史表族-宏观.md`（双写模型、八表全景、删除三层次）。前三篇讲的是流程**走过哪里**（PROCINST 总账 / ACTINST 脚印 / TASKINST 人工任务），这篇讲流程**带着什么数据在走**。
>
> 标本：
> - **test-0004** `175ffafb-84bc-11f1-b2ab-5eea1d7fcc1d`（已办结，**5 行**：`days` / `reason` / `initiator` / `approved` / `comment`）
> - **test-0005** `6a897d3d-84d2-11f1-b2ab-5eea1d7fcc1d`（在途，**3 行**：`days` / `reason` / `initiator`——审批结论还没诞生）

---

## 一、一句话定位

> **`ACT_HI_VARINST` 一个流程变量一行——记录每个变量的"最终值"（不是变更史）。**

流程实例不是空着手走路径的：请了几天假（`days`）、什么事由（`reason`）、谁发起的（`initiator`）、批没批（`approved`）、什么意见（`comment`）——这些数据全程跟着实例流转。前三张表回答"走了哪里、谁办的"，这张表回答**"单子上填的是什么"**。

注意定位里的限定词：**最终值**。`approved` 若被改过三次，这里只有最后一次的值。想要"每一次变更"是 `ACT_HI_DETAIL` 的事（`full` 级别才写，见第六节）。

---

## 二、诞生背景：路径之外，还有数据

回看你的 leave 流程走一遍，变量在三个时刻诞生：

```
发起时   start(key, businessKey, variables)     → days=2, reason=…   （你传的）
         flowable:initiator="initiator"          → initiator='3'      （引擎写的）
办理时   complete(taskId, variables)             → approved=true, comment=…（manager 填的）
```

流程办完，`ACT_RU_VARIABLE` 随实例清空（Day 13 实测四表归零）。如果没有历史侧这份存档，那么——

- 「历史详情页看这单当时填的什么」→ 无从谈起
- 「审批结论是通过还是驳回」→ 只知道走完了，不知道结论
- 「统计本月平均请假天数」→ 数据没了

**审批的价值一半在数据，不在路径。** 路径大家都一样（都走 `startEvent → 审批 → end`），每单不一样的恰恰是变量。所以变量必须和路径一样进历史——这就是本表。

### `initiator`：一份信息记两处的范本

`03` 篇讲过 `ACT_HI_PROCINST.START_USER_ID_` 记发起人。本表里又有一行 `initiator='3'`，同一信息记了两处，**不是冗余失误**：

| | `START_USER_ID_`（PROCINST 字段） | `initiator`（变量） |
|---|---|---|
| 给谁用 | **人查**（`my-started` 过滤、历史列表展示） | **流程自己用**——BPMN 表达式里可写 `${initiator}` |
| 谁写入 | 引擎自动 | `flowable:initiator="initiator"`（`leave.bpmn20.xml:20` 显式声明的名字） |

典型用法：驳回后回到发起人节点 `flowable:assignee="${initiator}"`——引擎流转时要在**变量**里解析这个表达式，去 PROCINST 字段里翻不着。字段面向档案，变量面向执行，两个消费方两份存储。

---

## 三、孪生表：`ACT_RU_VARIABLE`

标准双写，`02` 篇 ACTINST 的剧本重演一遍：

| | `ACT_RU_VARIABLE` | `ACT_HI_VARINST` |
|---|---|---|
| 装什么 | 在途实例的变量（引擎流转要读，如网关条件 `${days > 3}`） | 全部（含在途） |
| 实例完结时 | **删除**（Day 13 实测归零） | **保留** |
| 谁在用 | 引擎表达式求值 + `taskService.getVariables()` | 历史查询 |

时间线对着标本看：

```
发起 test-0004        RU 3 行 / HI 3 行        （双写，days/reason/initiator）
manager 办理并传入
approved + comment    RU 短暂 5 行 / HI 5 行   （新变量同样双写）
实例随即完结          RU 0 行 / HI 5 行        （RU 清空，HI 成唯一档案）
```

test-0005 现在就停在第一行的状态：RU / HI 各 3 行并存。**没有 `approved`——审批结论这个变量在办理那一刻才诞生**，在途单子天然没有结论，这不是 bug 是常识,但前端渲染历史详情时要处理好"字段可能还不存在"。

### Day 13 那条重要附注：变量挂在实例上,不挂在任务上

实测发现三个变量的 `TASK_ID_` **全为空**、只有 `PROC_INST_ID_` 有值——变量属于**实例**这个作用域。但 `detail` 接口用 `taskService.getVariables(taskId)` 照样拿到了它们：**引擎沿执行树向上找**，任务级没有就去实例级取。

反过来也存在"任务级私有变量"：`taskService.setVariableLocal()` 写的变量 `TASK_ID_` 有值、只在该任务可见（典型用途：会签场景每人各写一份意见,互不覆盖）。你项目当前全是实例级变量，但读这张表时 `TASK_ID_` 是否为空,就是区分两种作用域的开关。

---

## 四、一张表存所有类型：多态类型列

这张表最独特的设计问题：`days` 是数字、`reason` 是字符串、`approved` 是布尔——**一张表怎么存任意类型的值？**

Flowable 的答案是 **`VAR_TYPE_` 当类型标签 + 多个值列择一存放**：

| `VAR_TYPE_` | 值存在哪 | 你的标本 |
|---|---|---|
| `string` | `TEXT_` | `reason`、`comment`、`initiator`（`TEXT_='3'`——**注意是字符串**） |
| `integer` / `long` / `short` | `LONG_` | `days` → `LONG_=2` |
| `boolean` | `LONG_`（1/0） | `approved` → `LONG_=1`（Day 13 实测；SQL Server 无原生 bool） |
| `double` | `DOUBLE_` | （暂无） |
| `date` | `LONG_`（时间戳毫秒） | （暂无） |
| `serializable` | `BYTEARRAY_ID_` → 指向 `ACT_GE_BYTEARRAY` | （暂无，**最好永远没有**，见踩坑 4） |
| `json` | `TEXT_`（大 JSON 进 BYTEARRAY） | （暂无，存复杂结构的正道） |

三个要点：

1. **读值必须先看 `VAR_TYPE_` 再选列**。写 SQL 统计时 `SUM(TEXT_)` 是拿不到请假天数的，数字在 `LONG_` 里。
2. **API 层类型保真**。Day 13 实测 `detail` 返回 `days` 是数字 `2`、`initiator` 是字符串 `"3"`——引擎按 `VAR_TYPE_` 还原成 Java 类型再给你，没有被压成字符串。P6 表单渲染可以直接信任类型。
3. **`serializable` 是逃生舱不是常规通道**。Java 对象序列化成字节塞进 `ACT_GE_BYTEARRAY`,SQL 查不了、类改版反序列化就炸。要存结构化数据用 `json` 类型或干脆存业务表主键（`businessKey` 的思路,见 `03` 篇）。

> 这个"类型标签 + 多列择一"模式在 `ACT_RU_VARIABLE` / `ACT_HI_DETAIL` 里长得一模一样,看懂一张等于看懂三张。

---

## 五、功能结构：字段分组

### 组 1 · 身份：这是哪个变量

| 字段 | test-0004 里的值 | 说明 |
|---|---|---|
| `ID_` | （uuid） | 变量行自己的 id |
| `NAME_` | `days` / `reason` / `initiator` / `approved` / `comment` | **变量名，查询的主入口** |
| `VAR_TYPE_` | `integer` / `string` / `boolean` | 类型标签（第四节） |
| `REV_` | 1 或更高 | 每次 `setVariable` 覆盖 +1——**REV_ 高说明被改过,但改成过什么这里不知道** |

### 组 2 · 归属与作用域

| 字段 | 说明 |
|---|---|
| `PROC_INST_ID_` | 属于哪条实例——族表统一的挂载点 |
| `EXECUTION_ID_` | 哪个执行游标上（并行分支各自的局部变量靠它区分） |
| `TASK_ID_` | **为空 = 实例级；有值 = `setVariableLocal` 的任务级私有变量**（第三节） |
| `SCOPE_ID_` / `SUB_SCOPE_ID_` / `SCOPE_TYPE_` | CMMN 案例域用，纯 BPMN 恒空 |

### 组 3 · 值（多列择一）

| 字段 | 说明 |
|---|---|
| `TEXT_` | 字符串值；也存数字的字符串副本（引擎顺手写的,别当主数据用） |
| `TEXT2_` | 辅助列（如 json 类型溢出提示） |
| `LONG_` | 整数 / 布尔(1/0) / 日期(时间戳) |
| `DOUBLE_` | 浮点 |
| `BYTEARRAY_ID_` | serializable / 超长 json 的字节引用，指向 `ACT_GE_BYTEARRAY` |

### 组 4 · 时间

| 字段 | 说明 |
|---|---|
| `CREATE_TIME_` | 变量首次写入时刻（`days` 是发起时，`approved` 是办理时——**两批变量的诞生时刻差了 2h24m，本身就是信息**） |
| `LAST_UPDATED_TIME_` | 最后一次覆盖时刻。与 `CREATE_TIME_` 不等 = 被改过 |

---

## 六、只存最终值：与 `ACT_HI_DETAIL` 的分工

设想 `approved` 被写过三次（先误点通过、又改驳回、最后改回通过）。本表里它**始终一行**，`LONG_` 是最后的值，`REV_` 变成 3——你知道它被改过,但**中间值永远丢失**。

要留每一次变更，是外围表 `ACT_HI_DETAIL` 的职责,且有两道门槛（`00` 篇讲过,这里复述关键）：

1. **必须 `full` 历史级别**——默认 `audit` 下 DETAIL 一行不写,你库里它是空的
2. **必须提前开**——历史是当时记的,事后调级别补不回来

取舍的实感：审批系统里"金额被改过几次、谁改的"是合规刚需时才开 `full`,代价是写入量最大档。你这个 demo 的变量只写不改（发起写三个、办理写两个,互不覆盖）,`audit` 档的 VARINST 就是全部真相,`REV_` 全是 1。

> 判断要不要 `full` 的口诀：**变量会被"改"才有变更史的需求；只会被"添"的流程,VARINST 已经等价于全史。**

---

## 七、能不能删

### 层次 1 · DROP 表 → ❌ 不行

同 `00` 篇。且历史表单回显、按变量搜实例全靠它,历史域会缺一条腿。

### 层次 2 · 不写入 → ⚠️ 与 ACTINST/PROCINST 同一档

`ACT_HI_VARINST` 在 **`activity` 级别**就开始写——和总账、脚印同档,**比 TASKINST 还低一档**。只有 `none` 能让它停写。

**关掉后失去什么**：

- 历史表单回显（P6 渲染器对已办结单子无数据可填）
- 审批结论展示（`approved`/`comment` 办完即蒸发）
- 按变量搜实例（"找出请假超过 3 天的单子"）
- 变量类报表（平均请假天数）

### 层次 3 · 删数据 → ✅ 随实例族删

粒度仍是**实例**（`03` 篇的"户主"模型）：`deleteHistoricProcessInstance(id)` 连带清掉该实例的所有变量行；`cascade=true` 删部署同理全灭。没有"只删某个变量的历史"的常规 API——变量是实例的从属数据,跟着户主走。

---

## 八、实际应用场景

### 场景 1 · 历史详情页的表单回显（Day 18 / P6 会撞上）

在途任务的变量你已经会取了（`detail` 接口的 `taskService.getVariables`）。但**实例一办结,这条路就断了**——RU 表没行了,runtime/task API 查不到。历史侧的对应写法：

```java
historyService.createHistoricVariableInstanceQuery()
        .processInstanceId(instanceId)
        .list();     // 返回 HistoricVariableInstance，getValue() 已按 VAR_TYPE_ 还原类型
```

Day 18 历史详情页 = `03` 篇的总账行（谁发起/何时/结局）+ `02` 篇的轨迹（走了哪些步）+ **本表的变量（单子上填了什么、批的什么意见）**,三篇在那一页会师。

### 场景 2 · 审批结论的呈现

前端拿到 5 个变量后,`approved`/`comment` 就是"审批结果"栏的数据源。注意两点：在途单子**没有这两个变量**（第三节）,渲染要容错；将来多级审批时两个审批人都写 `comment` 会**互相覆盖**（实例级变量只有一份）——那时要么变量名带节点前缀（`managerComment`/`directorComment`）,要么改用 `setVariableLocal` + 读 `ACT_HI_COMMENT`,设计 P6 表单时留个心眼。

### 场景 3 · 按变量搜实例

```java
historyService.createHistoricProcessInstanceQuery()
        .variableValueGreaterThan("days", 3)     // 请假超 3 天的单子
        .list();
```

查询 API 里的 `variableValue*` 系列底层就是 join 本表。**性能提示**：这类查询在 `NAME_` + 值列上翻,变量行数 = 实例数 × 平均变量数,量大后是历史域最先变慢的查询,生产里高频筛选条件（如单据类型、金额区间）更适合提升为 `BUSINESS_KEY_` 或业务表字段。

### 场景 4 · 变量类报表

```sql
-- 本月已办结请假单的平均天数（注意：数字在 LONG_，不在 TEXT_）
SELECT AVG(v.LONG_ * 1.0) AS avg_days
FROM ACT_HI_VARINST v
JOIN ACT_HI_PROCINST p ON p.PROC_INST_ID_ = v.PROC_INST_ID_
WHERE v.NAME_ = 'days'
  AND p.END_TIME_ >= '2026-07-01' AND p.DELETE_REASON_ IS NULL;
```

与 `03` 篇场景 2 的实例统计天然一对：那边算"多少单、多久",这边算"单子里的业务数字"。join 条件与办结判据全复用 `03` 篇。

---

## 九、踩坑清单

| # | 坑 | 后果 | 对策 |
|---|---|---|---|
| 1 | 办结后仍用 `taskService`/`runtimeService` 取变量 | 查不到/报错（RU 已清） | 历史侧用 `HistoricVariableInstanceQuery`（场景 1） |
| 2 | 以为这张表有变更史 | 中间值早丢了,审计报告写不出来 | 只存最终值；要全史提前开 `full`（事后开无效） |
| 3 | SQL 统计直接读 `TEXT_` | 数字/布尔根本不在那列 | 先看 `VAR_TYPE_` 选列：数字/布尔/日期在 `LONG_`（第四节） |
| 4 | 往变量里塞大对象/实体类（serializable） | `ACT_GE_BYTEARRAY` 膨胀、SQL 不可查、类改版反序列化炸 | 存业务表主键或 json；对象本体留在业务库 |
| 5 | 在途单子当然有 `approved` | 前端渲染 undefined | 结论变量办理时才诞生（test-0005 只有 3 行）,渲染要容错 |
| 6 | 因为 `detail` 拿到了变量,以为变量挂在任务上 | 作用域理解错,会签设计翻车 | `TASK_ID_` 为空 = 实例级,`getVariables` 是沿执行树向上取的（Day 13 实测） |
| 7 | 变量名手滑拼错 | 引擎**不校验**,悄悄新建一个变量,网关条件 `${days > 3}` 解析不到真值 | 变量名是弱契约：前端表单字段名、`complete` 传参、BPMN 表达式三处必须人肉对齐——P6 表单设计器的 schema 正该管住这件事 |
| 8 | 多级审批都写 `comment` | 后一个覆盖前一个 | 变量名带节点前缀,或 `setVariableLocal`/`ACT_HI_COMMENT`（场景 2） |

---

## 十、和你项目的连接点

| 位置 | 关系 |
|---|---|
| `StartProcessInstanceRequest.variables` | 发起批变量的入口（`days`/`reason` 由此进来） |
| `leave.bpmn20.xml:20` `flowable:initiator` | `initiator` 变量的声明处,与 `START_USER_ID_` 一信息两处存（第二节） |
| `CompleteTaskRequest.variables` | 办理批变量的入口（`approved`/`comment` 由此进来） |
| `FlowableTaskServiceImpl.detail()` | 在途变量的消费方（`getVariables` 沿执行树上取）；办结后的对应方案见场景 1 |
| Day 18「历史」详情页 | 总账 + 轨迹 + 变量三篇会师之地 |
| P6 表单设计器/渲染器 | schema 字段名 = 变量名（弱契约的治理者,踩坑 7）；类型保真已实测,渲染可信任类型 |
| P5 之后的网关流程 | `${days > 3}` 之类条件表达式读的就是 RU 侧的这份变量 |

**两条标本对照速查**：

```
test-0004（办结，5 行）   days=2(integer→LONG_)  reason(string→TEXT_)  initiator='3'(string)
                          approved=true(boolean→LONG_=1)  comment(string)
                          发起批与办理批的 CREATE_TIME_ 相差 ≈2h24m
                          RU 侧 0 行——HI 是唯一档案

test-0005（在途，3 行）   days / reason / initiator——没有 approved/comment
                          （审批结论在办理那一刻才诞生）
                          RU 侧同样 3 行并存,引擎流转随时要读
```
