# 06 · 重置后 knife4j 重测步骤（Day 12 · 发起流程实例）

> 场景：接着 `process_deploy/06`（Day 11）跑完的现场——库里只有一条 **v1 激活定义** `leaveProcess:1:…`，从"发起实例"开始往下走。
>
> 与 `03-操作步骤.md` 同构，但按"重置后从零、Day 11 刚跑完"的实际现场重排，每步讲清「为什么测 + 该看到什么」。测一步勾一步，通过后回填 `04-验证清单.md`。

---

## 一、Day 12 在测什么

Day 11 把 BPMN "上架"成了静态的**流程定义**；Day 12 才让流程真正**跑起来**——把定义变成一条运行中的**实例**，数据从仓库表 `ACT_RE_*` 落进运行时表 `ACT_RU_*`。它是整条状态机的起点：没有实例，Day 13 的待办、Day 14 的历史都无从谈起。

发起一条实例，引擎会往**四张运行时表**写入：

| 表 | 存什么 | 发起后 |
|---|---|---|
| `ACT_RU_EXECUTION` | 实例本身 + 执行游标（当前走到哪） | 2 行 |
| `ACT_RU_TASK` | 当前待办任务 | 1 行（停在经理审批） |
| `ACT_RU_VARIABLE` | 流程变量 | 3 行（days / reason / initiator） |
| `ACT_RU_IDENTITYLINK` | 任务候选人/候选组 | 1 行（GROUP_ID_='manager'） |

4 个接口（context-path `/workflow`，`http://localhost:9090/workflow/doc.html`）：

| 方法 | 路径 | 作用 |
|---|---|---|
| POST | `/process-instance/start` | 发起（按 key 用最新版，当前用户记为发起人） |
| GET | `/process-instance/page` | 运行中实例分页（可按 definitionKey 过滤） |
| GET | `/process-instance/my-started` | 我发起的运行中实例 |
| DELETE | `/process-instance/{instanceId}?reason=` | 终止 |

测试目的三层：**① 接口行为**（正常/异常返回统一 `R`）、**② 引擎副作用**（四张 `ACT_RU_*` 表被正确写入/清除）、**③ 权限隔离**（`my-started` 只看自己发起的）。

---

## 二、准备：换 employee 账号

⚠️ 关键切换点：**Day 12 起用 employee 账号**（发起人要记成员工，Day 13 才好用 manager 去审）。

1. `POST /auth/login` 用 **employee** 登录，token 粘进右上角 Authorize（把之前的 admin token 换掉）。
2. 记一下运行时表基线（此刻应全 0，还没发起过）：

```sql
SELECT COUNT(*) FROM ACT_RU_EXECUTION;
SELECT COUNT(*) FROM ACT_RU_TASK;
SELECT COUNT(*) FROM ACT_RU_VARIABLE;
```

---

## 三、步骤 1 · 发起一条实例（主路径）

`POST /process-instance/start`，body：

```json
{
  "processDefinitionKey": "leaveProcess",
  "businessKey": "test-0001",
  "variables": { "days": 3, "reason": "年假" }
}
```

> body 里传的是 **key**（`leaveProcess`），不是三段式 id——`start` 内部用 `.latestVersion()` 自动选最新版，现在只有 v1 就挑 v1。

**看响应**（`R.data` 是 `ProcessInstanceVO`）：
- `id` → 实例 id（**记下来**，看表和终止都用它）
- `processDefinitionId` → 应是 `leaveProcess:1:…`（挑中了 v1）
- `startUserId` → **应 = employee 的 userId**（发起人接线成功的证据）
- `suspended` → false

**随即看四张运行时表**（把 `{instanceId}` 换成响应的 id）：

```sql
-- ① 实例+游标：预期 2 行，START_USER_ID_ 有值（= employee userId）
SELECT ID_, PROC_INST_ID_, PARENT_ID_, PROC_DEF_ID_, BUSINESS_KEY_, START_USER_ID_, ACT_ID_
FROM ACT_RU_EXECUTION WHERE PROC_INST_ID_ = '{instanceId}';

-- ② 当前任务：预期 1 行，停在 managerApprove（经理审批），ASSIGNEE_ 此刻为 null（还没人认领）
SELECT ID_, NAME_, TASK_DEF_KEY_, ASSIGNEE_ FROM ACT_RU_TASK WHERE PROC_INST_ID_ = '{instanceId}';

-- ③ 变量：预期 3 行 —— days(integer)、reason(string)、initiator(string, = employee userId)
SELECT NAME_, TYPE_, TEXT_, LONG_ FROM ACT_RU_VARIABLE WHERE PROC_INST_ID_ = '{instanceId}';

-- ④ 身份链：预期 2 行 ——
--    (a) starter：TYPE_='starter'、USER_ID_= 发起人、挂在实例级(PROC_INST_ID_ 有值)
--    (b) candidate：TYPE_='candidate'、GROUP_ID_='manager'、挂在任务级(TASK_ID_ 有值、PROC_INST_ID_ 为空)
--    注意 candidate 是任务级、PROC_INST_ID_ 为空，不能用 PROC_INST_ID_ 过滤，否则漏掉它
SELECT TYPE_, GROUP_ID_, USER_ID_, TASK_ID_, PROC_INST_ID_ FROM ACT_RU_IDENTITYLINK;
```

**该看到的现象**：
- 表① **2 行**：一行代表"流程实例"、一行代表"执行游标"（当前走到哪）。简单流程里俩长得像，不是重复。
- 表③ 的 `initiator` 变量来自 BPMN 的 `flowable:initiator="initiator"`，和表① 的 `START_USER_ID_` 是**两处各记一份发起人**，都应 = employee userId。
- 表④ 的 `manager` 候选组，就是 Day 13"只有 manager 能看到这条待办"的根据。

---

## 四、步骤 2 · 三种异常路径

**目的**：确认失败都走统一 `R` 错误结构，而不是把引擎生硬异常/500 抛给前端。

| # | 怎么造 | 预期 |
|---|---|---|
| 1 | body 里 `processDefinitionKey` 改成 `"noSuchProcess"` | 「流程定义不存在：noSuchProcess」（`def == null` 分支） |
| 2 | body 里**删掉** `processDefinitionKey` 字段 | 400 参数校验错误（`@NotBlank` + `@Valid` 生效） |
| 3 | 先 `PUT /process-definition/{v1的definitionId}/suspend` 挂起，再发起 | 「流程定义已挂起，无法发起」（`def.isSuspended()` 分支） |

> ⚠️ 第 3 步测完**务必 `activate` 把 v1 激活回来**，否则后面步骤发不起来。

---

## 五、步骤 3 · 查询两连 + 隔离

**目的**：验分页/排序/过滤，以及最关键的 `startedBy` 隔离。

1. 再用步骤 1 发起 **1–2 条**（`businessKey` 换成 `test-0002` 等，便于区分）。
2. `GET /process-instance/page`：应看到全部运行实例，**按发起时间倒序**，`total` 正确；再试 `definitionKey=leaveProcess`（有值）和 `definitionKey=xxx`（**应 0 条**）。
3. `GET /process-instance/my-started`：目前只有 employee 发起过，条数应**与 page 相同**。
4. **换 admin token 验隔离**（重点）：Authorize 里换成 **admin token**，再调 `my-started` → **应为 0 条**（admin 没发起过）；而 `page` 仍能看到全部。这一 0 一全，就是 `startedBy(UserContext.userId())` 过滤生效的铁证。

> 验完隔离记得**换回 employee token**再往下。

---

## 六、步骤 4 · 终止（清 terminate 欠账）

**目的**：验证「已写未测」的 `terminate()`——运行时表清空、但历史留痕。

1. 挑一条实例：`DELETE /process-instance/{instanceId}?reason=测试终止`
2. 复查：`page` 少一条；`ACT_RU_EXECUTION` / `ACT_RU_TASK` 里**该实例的行消失**。
3. 瞄一眼历史（Day 14 的正主，先确认留痕对）：

```sql
SELECT ID_, END_TIME_, DELETE_REASON_ FROM ACT_HI_PROCINST WHERE ID_ = '{instanceId}';
-- 预期：行还在，END_TIME_ 有值，DELETE_REASON_ = '测试终止'
```

> 这验证了"已完结的实例不在 RU 表里"——运行时清空但历史 HI 保留。

4. 对**不存在的 id** 再 DELETE 一次 → 「运行中的流程实例不存在」（`instance == null` 分支）。

---

## 七、步骤 5 · 清 Day 11 的 cascade 欠账

**目的**：Day 11 删部署时 `cascade=false` 遇在途实例的冲突分支，当时没实例走不到，现在补上。

前提：库里**还有至少一条运行中实例**（步骤 4 别全删光，没有就再发一条），且知道它跑在哪个部署上（`processDefinitionId` 里的 `key:version` 对应哪条 deployment）。

1. **cascade=false 分支**：`DELETE /process-definition/deployment/{deploymentId}?cascade=false`
   → 预期**失败**，报「删除失败：该部署下可能存在流程实例…」——你 Impl 里 catch 后转 `BizException` 的分支**第一次真正被触发**。
2. **cascade=true 分支**：同一个 deploymentId，`cascade=true`
   → 预期**成功**；复查三处：`ACT_RE_PROCDEF` 该版本消失、`ACT_RU_EXECUTION` 跑在该版本上的实例消失、`ACT_HI_PROCINST` 里它们的**历史也一并消失**（cascade 连历史一起删，这就是前端要二次确认的原因）。
3. **恢复现场**：若把唯一的 leave 部署删没了，重新 `POST /process-definition/deploy` 传一次 `leave.bpmn20.xml`，并**发起至少一条在途实例**，给 Day 13 备好料。

> deploymentId 怎么找：`processDefinitionId`（`leaveProcess:N:xxx`）里的 `key:version` 对应哪条 deployment，忘了就用 Day 11 那条 JOIN SQL 反查 `ACT_RE_PROCDEF` → `DEPLOYMENT_ID_`。

---

## 八、收尾

- 库里最好**留一条 employee 发起的在途实例**（停在经理审批），给 Day 13 直接当料。
- 去 `04-验证清单.md` 逐项打勾；疑问记进 `05-疑问与解答.md`；回填排期文档 Day 12 打卡行。

---

## 九、最容易踩的点

1. **start 传 key 不传三段式 id**：`processDefinitionKey` 填 `leaveProcess`，引擎自动选最新版；填三段式反而不对。
2. **发起人接线**：`startUserId` 和 `initiator` 变量都应 = employee userId。若为 null，检查 `Authentication.setAuthenticatedUserId` 是否在发起前被调用、且 `UserContext` 里确实有当前用户。
3. **隔离验证要换 token**：`my-started` 的差异只有换成没发起过的账号（admin）才看得出来。
4. **cascade 冲突分支依赖"有在途实例"**：步骤 5 前别把实例全终止了，否则又走不到那个分支。
5. **挂起测试记得激活回来**：步骤 2 第 3 项挂起 v1 后，务必 activate，否则后续发起全被拦。
