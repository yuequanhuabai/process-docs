# 06 · 恢复现场 + Day 13 knife4j 实测步骤（待办办理）

> 场景：Day 12 步骤 5 的 `cascade=true` 把 leave 相关数据**全清光了**（`ACT_RE_*` / `ACT_RU_*` / `ACT_HI_*` 归零）。本文从"重新铺料"开始，一路走到 Day 13 关闭。
>
> 与 `03-操作步骤.md` 同构，但按"空库起步"的实际现场重排，每步讲清「为什么测 + 该看到什么」。测一步勾一步，通过后回填 `04-验证清单.md`。
>
> 前置状态：Day 10/11/12 均已实测关闭（见 `../../测试进度断点.md`）。

---

## 一、Day 13 在测什么

Day 12 让流程**跑起来**并停在了「经理审批」。Day 13 要让它**往下走**——把停着的任务办掉，流程走到终点。

这一步是整条状态机上**唯一一次数据大搬家**：办理前数据在运行时表 `ACT_RU_*`，办理后实例完结，运行时表**清空**，全部落进历史表 `ACT_HI_*`。这也是 Day 14「我的已审批 / 历史轨迹」唯一的数据来源。

3 个接口（context-path `/workflow`，`http://localhost:9090/workflow/doc.html`）：

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/task/todo` | 我的待办（候选组 = 我的角色，或已指派给我） |
| GET | `/task/{taskId}` | 任务详情（含流程变量，办理前拉取） |
| POST | `/task/complete` | 办理（未认领则自动认领后办理） |

测试目的三层：**① 接口行为**（查得到 / 办得掉 / 异常友好）、**② 权限隔离**（只有 manager 看得到、办得了）、**③ 引擎副作用**（RU 清空 + HI 落库，尤其 `ASSIGNEE_` 有值）。

### 本轮涉及的账号

| 账号 | userId | role | 在本轮的角色 |
|---|---|---|---|
| employee | 3 | employee | 发起人；用来验"看不到别人的待办、办不了" |
| manager | 2 | manager | 审批人，主角 |
| admin | 1（以库为准） | admin | 第三方对照，验 `todo` 为 0 条 |

> `todo` 用 `taskCandidateGroup(me.getRole())` 匹配，BPMN 里写的是 `candidateGroups="manager"`——**能否看到待办，取决于你的 role 字符串是否等于 `manager`**，与用户名无关。

---

## 二、步骤 0 · 恢复现场（空库起步，必做）

⚠️ 库是空的，不铺料后面全走不动。

### 0-1 重新部署

`POST /process-definition/deploy`（`multipart/form-data`）

- `file`：选 `process-back/src/main/resources/processes/leave.bpmn20.xml`
- `name`：可填「请假流程」，留空也行

**看响应**：`R.data` 是 `ProcessDefinitionVO`
- `key` = `leaveProcess`
- `version` = **1**（库已清空，版本号从 1 重新开始，不会接着以前的 2 往上走）
- `id` 形如 `leaveProcess:1:<新的uuid>` —— **和昨天那个 `2695eea2-…` 不同**，别拿旧 id 去查

**记下两个 id**（后面步骤 5 之外也可能用到）：

```sql
SELECT ID_, KEY_, VERSION_, DEPLOYMENT_ID_ FROM ACT_RE_PROCDEF;
-- 预期 1 行；ID_ 是定义 id，DEPLOYMENT_ID_ 是部署 id，两者不同别搞混
```

### 0-2 用 employee 发起一条实例

Authorize 换成 **employee** 的 token（`POST /auth/login` 拿），然后 `POST /process-instance/start`：

```json
{
  "processDefinitionKey": "leaveProcess",
  "businessKey": "test-0004",
  "variables": { "days": 2, "reason": "病假" }
}
```

**记下响应里的 `id`**（实例 id），后面查表全靠它。

### 0-3 确认料铺好了

```sql
-- 预期 2 行（实例行 PARENT_ID_ 空 + 游标行 ACT_ID_=managerApprove）
SELECT ID_, BUSINESS_KEY_, ACT_ID_, START_USER_ID_ FROM ACT_RU_EXECUTION;

-- 预期 1 行：NAME_='经理审批'、TASK_DEF_KEY_='managerApprove'、ASSIGNEE_ 为 NULL（关键：未认领）
SELECT ID_, NAME_, TASK_DEF_KEY_, ASSIGNEE_, PROC_INST_ID_ FROM ACT_RU_TASK;

-- 预期 2 行：starter(实例级, USER_ID_=3) + candidate(任务级, GROUP_ID_='manager')
SELECT TYPE_, GROUP_ID_, USER_ID_, TASK_ID_, PROC_INST_ID_ FROM ACT_RU_IDENTITYLINK;
```

**把 `ACT_RU_TASK.ID_` 记下来**——这就是 taskId，步骤 2/3/4 都要用它。

> ✅ 到这里现场恢复完成，`04-验证清单.md`「Day 11 欠账」里的"测试现场已恢复"可以打勾了。

---

## 三、步骤 1 · 待办列表 + 三账号隔离（本块的安全点）

**目的**：验证 `todo` 的双条件查询（`or().taskCandidateGroup(role).taskAssignee(userId)`）与角色隔离。

依次换 token 调 `GET /task/todo`，**三行都对上才算数**：

| token | 预期条数 | 为什么 |
|---|---|---|
| **manager** | **1 条** | role=`manager` 命中候选组 |
| **employee** | **0 条** | role=`employee` 不在候选组，且没有指派给他的任务 |
| **admin** | **0 条** | 同上，admin 不是万能的——引擎只认候选组 |

manager 那一条要看清三个字段：
- `name` = `经理审批`
- `assignee` = **null**（还没认领，这是自动认领逻辑的前提）
- `createTime` 格式化正确（不是时间戳数字、不是 `2026-07-21T…` 的 ISO 串）

> 💡 这里 employee 的 0 条要特别理解：他是这条流程的**发起人**，但发起人 ≠ 办理人。`todo` 查的是"谁该办"，不是"谁相关"。发起人想看自己的单子，走的是 Day 12 的 `my-started`。

---

## 四、步骤 2 · 任务详情

**目的**：验证办理前的表单数据拉取（前端办理弹窗要靠它渲染）。

**manager token** 调 `GET /task/{taskId}`，看 `TaskFormVO`：

- `variables` 含 **3 项**：`days=2` / `reason=病假` / `initiator=3`
- `formKey` 为 **null**（Day 13 还没接表单设计器，P6 才会给它赋值）

> `taskService.getVariables(taskId)` 会**沿执行树向上**取到实例级变量——变量是挂在实例上的，不是挂在任务上的，但办理人在任务详情里就能看到全部。这是 Flowable 变量作用域的默认行为。

---

## 五、步骤 3 · 越权测试（先测坏路径，再测好路径）

⚠️ **顺序很重要**：必须在办理**之前**测越权，因为办掉之后任务就不在 `ACT_RU_TASK` 里了，再测只会得到"任务不存在"，验不到越权分支。

**目的**：证明接口本身是安全的，而不是"靠列表看不见来保护"。列表过滤只是**看不见**，taskId 一旦泄漏（比如从别人截图里抄来），裸接口就能被越权调用——`assertCanOperate` 就是补这个洞的。

用 **employee token**，拿步骤 0-3 记下的那个 taskId（模拟"泄漏"）：

| # | 调用 | 预期 |
|---|---|---|
| 1 | `GET /task/{taskId}` | 「你不在该任务的候选办理人范围内，无权操作」 |
| 2 | `POST /task/complete`（body 见下） | 同上，同样被拒 |

```json
{ "taskId": "<步骤0-3记下的taskId>", "variables": { "approved": true } }
```

再验参数校验（任意 token 均可）：

| # | 怎么造 | 预期 |
|---|---|---|
| 3 | body 里 `taskId` 传 `"noSuchTask"` | 「待办任务不存在或已办理：noSuchTask」 |
| 4 | body 里**删掉** `taskId` 字段 | 400 参数校验错误（`@NotBlank` + `@Valid` 生效） |

> 第 3 条的措辞值得留意：「不存在**或已办理**」——引擎的 `ACT_RU_TASK` 里查不到，可能是 id 错了，也可能是任务已经被办掉搬进历史了。运行时表分不清这两种情况，所以报错措辞把两种都涵盖了。

---

## 六、步骤 4 · 办理（主路径 · 数据大搬家）

**目的**：本块的正戏。验证自动认领 + 办结 + RU→HI 搬迁。

**换回 manager token**，`POST /task/complete`：

```json
{
  "taskId": "<步骤0-3记下的taskId>",
  "variables": { "approved": true, "comment": "同意" }
}
```

**看响应**：200。**看后端日志**：应打出 `任务已办理：taskId=…, taskKey=managerApprove, instanceId=…, assignee=2`——`assignee=2` 是自动认领生效的第一手证据。

### 4-1 运行时表：应全部清空

```sql
-- 四张 RU 表，该实例的行应全部消失
SELECT COUNT(*) FROM ACT_RU_EXECUTION;
SELECT COUNT(*) FROM ACT_RU_TASK;
SELECT COUNT(*) FROM ACT_RU_VARIABLE;
SELECT COUNT(*) FROM ACT_RU_IDENTITYLINK;
-- 预期：全 0
```

⚠️ **这不是 bug**。leave 流程只有一个审批节点，办掉它流程就走到 `endEvent` 完结了。实例一完结，运行时表就没它的位置了——RU 表只装在途的。

### 4-2 历史表：数据落在这里

```sql
-- ① 任务历史：ASSIGNEE_ 必须 = '2' ★★★
SELECT ID_, NAME_, TASK_DEF_KEY_, ASSIGNEE_, START_TIME_, END_TIME_, DURATION_
FROM ACT_HI_TASKINST WHERE PROC_INST_ID_ = '{instanceId}';

-- ② 变量历史：预期 5 行 —— days/reason/initiator + 办理时新增的 approved/comment
SELECT NAME_, VAR_TYPE_, TEXT_, LONG_ FROM ACT_HI_VARINST WHERE PROC_INST_ID_ = '{instanceId}';

-- ③ 活动轨迹：预期 3 行 startEvent → managerApprove → endEvent，END_TIME_ 都有值
SELECT ACT_ID_, ACT_NAME_, ACT_TYPE_, ASSIGNEE_, START_TIME_, END_TIME_
FROM ACT_HI_ACTINST WHERE PROC_INST_ID_ = '{instanceId}' ORDER BY START_TIME_;

-- ④ 实例历史：END_TIME_ 有值，且 DELETE_REASON_ 为 NULL（正常办结）
SELECT ID_, BUSINESS_KEY_, END_TIME_, END_ACT_ID_, DELETE_REASON_
FROM ACT_HI_PROCINST WHERE ID_ = '{instanceId}';
```

**四条里最要紧的是 ①**：`ACT_HI_TASKINST.ASSIGNEE_ = '2'`。

> Day 14 的「我的已审批」就是拿当前用户 id 去查这一列的。**这条不过，Day 14 白做**。`complete()` 里那段"未认领先 claim 再 complete"的代码，唯一目的就是兑现这个值——如果直接 complete 而不 claim，任务能办掉，但 `ASSIGNEE_` 会是 NULL，历史上就成了"没人办过的已办任务"。

**③ 和 ④ 的对照点**：
- `ACT_HI_ACTINST` 有 `endEvent` 一行 → 流程是**正常走到终点**的
- `ACT_HI_PROCINST.END_ACT_ID_` = `endEvent`（有值）、`DELETE_REASON_` = **NULL**

拿这两个字段和 Day 12 步骤 4 终止的那条对比：终止的那条 `END_ACT_ID_` 为空、`DELETE_REASON_` = '测试终止'。**「正常办结」和「被终止」就靠这两列区分**，前端历史列表要显示状态标签，判据就在这儿。

### 4-3 重复办理

对**同一个 taskId** 再调一次 `complete` → 预期「待办任务不存在或已办理：…」（它已经从 `ACT_RU_TASK` 搬走了）。

---

## 七、步骤 5 · 收尾与备料

Day 13 走完，库里已经没有在途实例了（唯一一条办结了）。**Day 14 需要两种料**才能把「我的已审批」和「历史轨迹」都验到：

1. **已办结的一条**：test-0004，步骤 4 刚产出 ✅
2. **在途的一条**：再用 employee 发起 `test-0005`（`days=4` / `reason=年假`），**不要办理**，留着给 Day 14 验证"运行中的实例也能查轨迹"（轨迹应只有 `startEvent` + `managerApprove` 两行，且 `managerApprove` 的 `END_TIME_` 为空）

> 这一条是 Day 12 那个意外发现的直接应用：HI 行在**发起时**就写入了，所以在途实例查历史轨迹也有数据，只是尚未完结的节点 `END_TIME_` 为空。

然后：
- 去 `04-验证清单.md` 逐项打勾
- 疑问记进 `05-疑问与解答.md`
- 回填 `../../05-重写排期计划.md` 的 Day 13 任务与打卡行
- 更新 `../../测试进度断点.md` 的现场与进度

---

## 八、最容易踩的点

1. **越权测试必须在办理之前做**：办掉后任务离开 `ACT_RU_TASK`，越权分支再也走不到，只会得到"任务不存在"，等于没测。
2. **重新部署后 id 全是新的**：版本号从 v1 重新开始，定义 id / 部署 id / 实例 id / taskId 都与昨天的不同，别拿旧 id 去查表。
3. **办理后 RU 表空了不是 bug**：单节点流程办完即完结，数据搬进 HI。想验"办完还有待办"需要多节点流程，本 demo 没有。
4. **`ASSIGNEE_ = '2'` 是 Day 14 的命门**：这条不过就别往下走了，先回头查 `complete()` 里的 claim 分支是否被跳过（`task.getAssignee() == null` 判断）。
5. **能否看到待办只取决于 role 字符串**：BPMN 里写死 `candidateGroups="manager"`，用户表里 role 字段必须**恰好等于** `manager`。role 拼错、大小写不一致都会导致 todo 空列表，而且**不报错**——静默查不到最难排查。
6. **三账号隔离要全测**：只测 manager 看到 1 条不算数，必须配上 employee 0 条 + admin 0 条的对照，才能证明是候选组过滤生效，而不是"库里恰好只有一条"。
