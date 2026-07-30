# 03 · ACT_HI_PROCINST —— 实例总账

> 先读 `00-历史表族-宏观.md`（双写模型、八表全景、删除三层次）。`01`/`02` 讲的是"树枝"（任务、活动），这篇讲"树根"。
>
> 标本：
> - **test-0004** `175ffafb-84bc-11f1-b2ab-5eea1d7fcc1d`（**已办结**，走到 endEvent）
> - **test-0005** `6a897d3d-84d2-11f1-b2ab-5eea1d7fcc1d`（**在途**，停在 `managerApprove`）
> - **test-0002** `4a9abb76-…`（**被终止**，Day 12 步骤 4 的实测留痕。⚠️ 该行已被步骤 5 的 cascade 抹除，库里查不到了，本篇引用的是 `../../process_instance/04-验证清单.md` 里当时记录的字段值）
>
> 三条标本恰好覆盖实例的**全部三种结局**——这张表的核心价值就是把结局记清楚。

---

## 一、一句话定位

> **`ACT_HI_PROCINST` 一条流程实例一行——记录"这一单的一生"：谁发起、何时起止、什么结局。**

它是四张核心表里**粒度最粗、行数最少**的一张，也是整棵历史树的**根**：

```
ACT_HI_PROCINST      1 行   ← 本篇（总账：一单一行）
   └─ ACT_HI_ACTINST 5 行   ← 02 篇（脚印：一步一行）
        └─ ACT_HI_TASKINST 1 行   ← 01 篇（人工任务：单独立账）
   └─ ACT_HI_VARINST 5 行   ← 04 篇（携带的数据）
```

`01` 是以人为中心，`02` 是以流程图为中心，这张表是**以"单"为中心**——业务方口中的"这笔申请""那个审批单"，落到数据库里就是这里的一行。

---

## 二、诞生背景：明明有明细，为什么还要总账

乍一想这张表是多余的：`ACT_HI_ACTINST` 已经记了每一步，实例什么时候开始（第一行的 `START_TIME_`）、什么时候结束（endEvent 行的 `END_TIME_`）、走没走完（有没有 endEvent 行），聚合一下不都能算出来？

能算，但有三个理由不该每次都算：

**理由 1：最高频的问题是实例级的。** "我的申请到哪了""这个月办结了多少单""平均一单走多久"——业务方问的从来是**单**，不是**步**。每问一次就 `GROUP BY PROC_INST_ID_` 聚合一遍明细，等于让会计每次报余额都从头加一遍流水。总账就是**预聚合**：一行直接回答一单。

**理由 2：有些属性天生属于实例，不属于任何一步。** `BUSINESS_KEY_`（业务单号）、`START_USER_ID_`（发起人）、`DELETE_REASON_`（为什么被终止）——这些挂在哪个节点上都不对，只能挂在实例上。没有这张表，它们无处安放。

**理由 3：结局要一锤定音。** "这单最后怎么样了"如果靠推断（有 endEvent 行 = 办结？没有 = 在途还是被终止？），逻辑散落在每个查询方手里，迟早推错。总账用 `END_TIME_` / `END_ACT_ID_` / `DELETE_REASON_` 三个字段把结局**显式记下来**（第五节详解）。

> 会计上这叫**总分账体系**：总账（PROCINST）管余额，明细账（ACTINST）管流水，两者数字必须能对上，但谁也替代不了谁。

---

## 三、与 `ACT_RU_EXECUTION` 的关系：不是简单孪生

`02` 篇里 `ACT_HI_ACTINST` 和 `ACT_RU_ACTINST` 是一比一孪生。这张表对应的运行时表是 `ACT_RU_EXECUTION`，但对应关系**不是一比一**——你 Day 12 发起后查库亲眼见过：

```
ACT_RU_EXECUTION   2 行   ← 实例行 + 游标行（并行分支时游标更多）
ACT_HI_PROCINST    1 行   ← 永远一行
```

原因是两边的职责不同：

| | `ACT_RU_EXECUTION` | `ACT_HI_PROCINST` |
|---|---|---|
| 记什么 | **执行状态**——引擎"现在走到哪"，并行时要多个游标各自领路 | **总账**——一单的静态档案，与走几路无关 |
| 结构 | 树（实例行是根，游标行是叶） | 平面，一行 |
| 实例完结时 | 整树**删除**（Day 12 终止后 2 行 → 0 行） | **保留**并补结束信息 |
| 谁在用 | 引擎流转 + 你的 `page`/`my-started`/`terminate` | 历史查询（在途的也查得到） |

两边的钩子是 **id 相同**：`ACT_RU_EXECUTION` 实例行的 `ID_` = `ACT_HI_PROCINST.ID_` = 你接口里传来传去的 `instanceId`。发起时双写、同 id 各记一行，完结时 RU 整树删掉，HI 这行升级成唯一档案。

> 顺带解释一个此前的困惑：为什么 `terminate` 对已办结实例报"运行中的流程实例不存在"——`ProcessInstanceServiceImpl.terminate()` 查的是 `ACT_RU_EXECUTION`，办结的实例那里已经没行了。**它在 HI 里还在**，只是终止接口的语义本来就只管在途的。

---

## 四、功能结构：字段分组

### 组 1 · 身份：这是哪一单

| 字段 | test-0004 里的值 | 说明 |
|---|---|---|
| `ID_` | `175ffafb-84bc-…` | 实例 id，全系统传来传去的就是它 |
| `PROC_INST_ID_` | `175ffafb-84bc-…`（同上） | **自引用，恒等于 `ID_`** |
| `BUSINESS_KEY_` | `test-0004` | 业务单号，发起时由你传入（`start` 接口的 `businessKey` 参数） |
| `NAME_` | 空 | 实例显示名，需代码显式 `setProcessInstanceName` 才有 |
| `REV_` | 2（办结后） | 乐观锁版本号，**1→2 是"发起时写入、完结时更新"的指纹**（Day 12 实测） |

`PROC_INST_ID_` 恒等于 `ID_` 看着傻，其实是**族表对齐**：ACTINST / TASKINST / VARINST 全都靠 `PROC_INST_ID_` 挂到实例上，总账自己也放一个同名列，四张表就能用同一个字段名做关联/过滤，写 SQL 不用记特例。

`BUSINESS_KEY_` 是**业务系统与引擎的接头暗号**：请假单在你自己的业务表里有主键，发起流程时把它塞进 `businessKey`，之后从业务单能查到流程（`processInstanceBusinessKey(key)`），从流程也能跳回业务单。不传就是 null，**事后没有优雅的补法**——要用就发起时传。

### 组 2 · 归属与层级

| 字段 | 说明 |
|---|---|
| `PROC_DEF_ID_` | 哪个流程定义的哪个版本（`leaveProcess:1:e531deaa-…`，**带版本号**） |
| `SUPER_PROCESS_INSTANCE_ID_` | 若本实例是被 callActivity 调起的子流程，指向父实例；顶级实例为空 |
| `TENANT_ID_` | 多租户，当前未用 |
| `CALLBACK_ID_` / `CALLBACK_TYPE_` / `REFERENCE_ID_` / `REFERENCE_TYPE_` / `PROPAGATED_STAGE_INST_ID_` | CMMN 案例管理 / 事件注册对接用，纯 BPMN 场景恒空，见到不用慌 |

`SUPER_PROCESS_INSTANCE_ID_` 与 `02` 篇的 `CALL_PROC_INST_ID_` 是**同一根线的两头**：父实例的 ACTINST 里那行 callActivity 用 `CALL_PROC_INST_ID_` 指下来，子实例的 PROCINST 用 `SUPER_PROCESS_INSTANCE_ID_` 指上去。将来做子流程,双向都能追。

### 组 3 · 人

| 字段 | test-0004 里的值 | 说明 |
|---|---|---|
| `START_USER_ID_` | `3`（employee） | 发起人。来源正是 `start()` 里那句 `Authentication.setAuthenticatedUserId(UserContext.userId())` |

只有这一个"人"字段——总账只记**谁发起**，不记谁办理（那是 TASKINST 的事）。`my-started` 的 `startedBy` 过滤，在 RU 侧对的是 `ACT_RU_EXECUTION.START_USER_ID_`，在 HI 侧对的就是这一列。

### 组 4 · 时间与结局（本表的灵魂）

| 字段 | 说明 |
|---|---|
| `START_TIME_` | 发起时刻 |
| `END_TIME_` | 结束时刻。**为空 = 还在途** |
| `DURATION_` | 全程毫秒数（冗余存储，理由同 `01` 篇） |
| `START_ACT_ID_` | 从哪个节点开始（`startEvent`，单入口流程恒定，多 start 的流程才有区分意义） |
| `END_ACT_ID_` | **从哪个节点结束**。正常办结 = 某个 endEvent 的 id；**被终止 = 空** |
| `DELETE_REASON_` | **非正常结束的原因**。正常办结 = 空；被终止 = 终止时传的 reason |

三条标本在这组字段上的对照，就是下一节的判据表。

---

## 五、三种结局的判据（前端会直接用）

一条实例只有三种结局，这张表用两个字段的组合把它们区分得干干净净：

| | `END_TIME_` | `END_ACT_ID_` | `DELETE_REASON_` | 标本 |
|---|---|---|---|---|
| **在途** | **空** | 空 | 空 | test-0005 |
| **正常办结** | 有值 | **`endEvent`** | 空 | test-0004 |
| **被终止** | 有值（`2026-07-21 10:57:09`） | **空** | **`测试终止`** | test-0002（Day 12 留痕） |

判定顺序建议：**先看 `END_TIME_`（空 = 在途），再看 `DELETE_REASON_`（有值 = 被终止），否则 = 办结**。

两个容易想歪的点：

1. **`END_ACT_ID_` 为空 ≠ 异常**——在途实例它也是空的，必须先用 `END_TIME_` 分流。它真正的贡献是在**多 endEvent 的流程**里回答"从哪个口出去的"（比如「审批通过结束」和「驳回结束」是两个 endEvent，出口即结论）。你的 leave 流程只有一个出口,暂时体现不出来。
2. **`DELETE_REASON_` 有值 ≠ 这行被删了**——恰恰相反，行还好好在这，它记的是"当初为什么被掐断"。真正的删除（`cascade=true`）是整行蒸发，连这个字段一起没了——test-0002 的现状就是活例：先被终止（留痕可查），后被 cascade（痕也没了）。

> 这张判据表将来直接翻译成前端的状态列渲染：Day 16「实例/我的发起」页和 Day 18「历史」页的 `进行中 / 已完成 / 已终止` 三色 tag，数据依据全在这里。

---

## 六、能不能删

### 层次 1 · DROP 表 → ❌ 不行

同 `00` 篇：schema 校验失败或自动重建。而且这张表是族表的根，`deleteHistoricProcessInstance` 等历史运维 API 都以它为入口，缺了它整个历史域瘫痪。

### 层次 2 · 不写入 → ⚠️ 几乎做不到"只关它"

`ACT_HI_PROCINST` 和 ACTINST、VARINST 一样在 **`activity` 级别**就开始写入——**只有 `none` 才能让它停写**。也就是说：

- 调到 `activity`：TASKINST 停写，**本表照写**
- 调到 `none`：本表停写，但**其余七张也全停了**

没有任何一档是"关总账、留明细"的——总账是根，明细都靠 `PROC_INST_ID_` 挂在它上面，只留明细不留根的档位不存在，这个设计本身就在告诉你它有多基础。

**关掉（`none`）后失去什么**：实例历史列表、发起人追溯、办结/终止判据、时长统计——外加其余七张表的全部功能。对审批系统等于自废武功。

### 层次 3 · 删数据 → ✅ 可以，且它是删除的"户主"

历史数据删除的粒度是**实例**，入口就是这张表：

- `historyService.deleteHistoricProcessInstance(id)`：以本表一行为户主，**连带清掉全族**（ACTINST / TASKINST / VARINST 及外围表中属于该实例的行）
- `deleteDeployment(id, true)`：cascade 按定义把名下所有实例连历史一起抹——Day 12 步骤 5 你亲眼看着本表从 3 行归 0，**连 test-0002 刚验完的终止留痕也一并蒸发**
- 定时归档：引擎自带 `enable-history-cleaning`（默认关，见 `application.yml` 注释），按 `history-cleaning-after: 365d` 定期清理——它清的也是"N 天前**办结**的实例"整族，判定依据还是本表的 `END_TIME_`

> 复述一遍那条业务陷阱（`00` 篇讲过，本表是主角）：**`terminate` 留 HI（业务作废，可审计"谁终止、为什么"）；`cascade=true` 连 HI 抹掉（当它没存在过）**。前端删部署的二次确认拦的就是后者。

---

## 七、实际应用场景

### 场景 1 · "我的发起"的完整版（Day 16 会撞上）

你现在的 `my-started` 查的是 `RuntimeService`：

```java
runtimeService.createProcessInstanceQuery()
        .startedBy(UserContext.userId())   // 只翻 ACT_RU_EXECUTION
```

**副作用：实例一办结（或被终止），就从"我的发起"里消失了**——RU 表里没行了。employee 会发现自己昨天发的申请批完之后列表里找不到，像被吞了。

完整版要换到 HI 侧：

```java
historyService.createHistoricProcessInstanceQuery()
        .startedBy(userId)                 // 翻 ACT_HI_PROCINST，在途 + 办结 + 终止全都在
        .orderByProcessInstanceStartTime().desc();
```

再配合第五节的判据表渲染状态列。**Day 16 做「我的发起」页时二选一**：要么整页改查 HI（推荐，一页看全生命周期），要么 RU 版叫"进行中的发起"、另开 HI 版做历史——总之现状的 `my-started` 不是成品，是半成品。

### 场景 2 · 实例级统计报表

```sql
-- 本月办结量、平均时长（毫秒）
SELECT COUNT(*) AS cnt, AVG(DURATION_) AS avg_ms
FROM ACT_HI_PROCINST
WHERE END_TIME_ >= '2026-07-01' AND DELETE_REASON_ IS NULL;
```

和 `02` 篇的瓶颈分析分工明确：这里按**单**统计（一单全程多久、月办结多少），ACTINST 按**步**统计（哪一环最拖）。管理层看这张，流程优化看那张。

### 场景 3 · 业务单号互查

```java
// 从业务单号找流程实例（历史的也能找到）
historyService.createHistoricProcessInstanceQuery()
        .processInstanceBusinessKey("test-0004")
        .singleResult();
```

前提是发起时传了 `businessKey`。你的 `start` 接口参数已经留好了这个口子，将来业务表单落库拿到主键后传进来即可。

### 场景 4 · 终止审计

"这单谁给终止的？为什么？"——`DELETE_REASON_` 记了原因（你的 `terminate` 接口不传就落"手动终止"）。但注意**引擎不记"谁"终止的**，`DELETE_REASON_` 只是一段文本。要留人就得约定格式（比如 reason 里拼上操作人 id），或另写 `ACT_HI_COMMENT`——这也是 Day 31 复查「terminate 任何人可调」鉴权问题时值得一并考虑的点。

---

## 八、踩坑清单

| # | 坑 | 后果 | 对策 |
|---|---|---|---|
| 1 | 用 RU 查"我的发起" | 实例一办结就从列表消失，用户以为丢单 | 全量列表查 `HistoricProcessInstanceQuery`（场景 1） |
| 2 | 拿 `END_ACT_ID_` 空当"被终止" | 在途实例全被误判 | 先 `END_TIME_` 分流，再看 `DELETE_REASON_`（第五节判定顺序） |
| 3 | 把 `DELETE_REASON_` 有值理解成"已删除" | 审计逻辑写反 | 有值 = 被终止但**留痕仍在**；真删除是整行没了 |
| 4 | 忘传 `businessKey` | 业务单据与流程失联，事后补不了 | 发起时就传（`start` 已留参数位） |
| 5 | 按 `PROC_DEF_ID_` 精确匹配统计 | 定义升版后（v1/v2 id 不同）统计漏掉旧版实例 | 想按流程种类统计就 join `ACT_RE_PROCDEF` 用 KEY_，或查询侧用 `processDefinitionKey` |
| 6 | 以为在途实例查 HI 查不到 | 白做限制 | 双写模型，发起时行就在了，`END_TIME_` 空而已（Day 12 实测） |
| 7 | 指望引擎记"谁终止的" | 审计缺主语 | `DELETE_REASON_` 只是文本，操作人要自己约定记法（场景 4） |

---

## 九、和你项目的连接点

| 位置 | 关系 |
|---|---|
| `ProcessInstanceServiceImpl.start()` | 本表行的**出生地**：`Authentication.setAuthenticatedUserId` → `START_USER_ID_`；`businessKey` 参数 → `BUSINESS_KEY_` |
| `ProcessInstanceServiceImpl.terminate()` | `DELETE_REASON_` 的写入方（不传默认"手动终止"）；只扫 RU 所以对已办结实例报"不存在" |
| `ProcessInstanceServiceImpl.myStarted()` | ⚠️ 半成品：RU 侧只见在途，完整版见场景 1，**Day 16 落地时决策** |
| `FlowableHistoryServiceImpl.activities()` | 以本表的 `ID_`（instanceId）为入口下钻 ACTINST；「运行中也可查」的依据 = 本表发起时即有行 |
| Day 16「实例/我的发起」页 | 状态列三色 tag 用第五节判据表 |
| Day 18「历史」页 | 实例历史列表的数据源 |
| Day 31 复查项 | terminate 鉴权 + "谁终止的"审计记法（场景 4）可一并考虑 |

**三条标本对照速查**：

```
test-0004（办结）   END_TIME_ 有值   END_ACT_ID_='endEvent'   DELETE_REASON_ 空
                    START_USER_ID_='3'  BUSINESS_KEY_='test-0004'  REV_=2
                    全程 ≈2h24m（12:24 发起 → 14:48 办结，等人占了绝对大头）

test-0005（在途）   END_TIME_ 空 ← 唯一判据   其余结局字段全空   REV_=1
                    RU 侧同 id 还有实例行+游标行；办掉或终止前，两边并存

test-0002（终止）   END_TIME_=10:57:09   END_ACT_ID_ 空   DELETE_REASON_='测试终止'
                    DURATION_=2823177（≈47m）  REV_ 1→2
                    ⚠️ 已被 cascade 抹除，此处为 Day 12 文档留痕——它的一生本身
                    就是"终止留痕、cascade 灭痕"两种删除语义的活教材
```
