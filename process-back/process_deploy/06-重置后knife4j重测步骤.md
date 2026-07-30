# 06 · 重置后 knife4j 重测步骤（Day 11 · 从零重走）

> 场景：跑过 `sql/reset-flowable.sql` 把引擎表清空、后端重启、库处于"从未部署过任何流程"的干净状态，从 Day 11 部署环节开始重走完整链路。
>
> 与 `03-操作步骤.md` 同构，但按"重置后从零"的实际现场重新串了一遍，每步讲清「为什么测 + 该看到什么」。测一步勾一步，通过后回填 `04-验证清单.md`。

---

## 一、Day 11 在测什么

Day 11 是「流程定义接口」——请假流程的**"上架"环节**。BPMN 文件本身只是一份 XML，必须先"部署"进引擎，才会变成一条可被发起的**流程定义**。没有定义，Day 12 就没东西可发起。

Flowable 部署一份 BPMN 会落到**三张仓库表**，这是本次验证的主线：

| 表 | 存什么 | 一次部署产生 |
|---|---|---|
| `ACT_RE_DEPLOYMENT` | 部署批次（一次 deploy = 一行） | 1 行 |
| `ACT_GE_BYTEARRAY` | 部署里的资源文件（xml 原文 + 自动生成的 png 流程图） | 2 行 |
| `ACT_RE_PROCDEF` | 解析出来的流程定义（key/version/挂起状态） | 1 行 |

5 个接口（context-path `/workflow`，全程 `http://localhost:9090/workflow/doc.html`）：

| 方法 | 路径 | 作用 |
|---|---|---|
| POST | `/process-definition/deploy` | 部署（multipart 传 BPMN 文件） |
| GET | `/process-definition/page` | 定义分页（`latestOnly` 可选） |
| PUT | `/process-definition/{definitionId}/suspend` | 挂起 |
| PUT | `/process-definition/{definitionId}/activate` | 激活 |
| DELETE | `/process-definition/deployment/{deploymentId}?cascade=` | 按部署删除 |

测试目的三层：**① 接口行为**（正常/异常返回统一 `R`）、**② 引擎副作用**（三张表被正确写入/清除）、**③ 版本机制**（同 key 重复部署自动升版）。

---

## 二、准备（步骤 0）

1. **确认后端已重启**、库是刚重置的空表状态。启动日志应能看到 Flowable **建表**、且**没有**自动部署日志（`check-process-definitions: false`）。
2. **登录拿 token**（employee 或 admin 都行，部署接口不分角色），粘进右上角 **Authorize**（裸 token，不加 `Bearer ` 前缀）。
3. SQL 客户端连 `flowable_db2`，记基线，此刻**三张表都应为 0 行**：

```sql
SELECT COUNT(*) FROM ACT_RE_DEPLOYMENT;
SELECT COUNT(*) FROM ACT_GE_BYTEARRAY;
SELECT COUNT(*) FROM ACT_RE_PROCDEF;
```

---

## 三、步骤 1 · 部署一份 BPMN（主路径）

**目的**：验证"上架"成功——一次 deploy 在三张表里各种下对应的行，并返回 `version:1`。

`POST /process-definition/deploy`，这是 **multipart 表单**（不是 JSON）：
- `file` → 选 `process-back/src/main/resources/processes/leave.bpmn20.xml`
- `name` → 留空（缺省用文件名）

**看响应**（`R.data` 是 `ProcessDefinitionVO`）：
- `id` → 三段式 `leaveProcess:1:xxxx`（key:version:序号）——**记下来**，挂起/激活要用它
- `key` → `leaveProcess`
- `version` → **1**（第一次部署）
- `deploymentId` → **记下来**，删除要用它（注意和 `id` 不是一回事）
- `suspended` → `false`
- `resourceName` → `leave.bpmn20.xml`
- `diagramResourceName` → 引擎自动生成的 png 名（非 null）

**随即看三张表**：

```sql
-- ① 部署批次：预期 1 行，NAME_ = leave.bpmn20.xml
SELECT ID_, NAME_, DEPLOY_TIME_ FROM ACT_RE_DEPLOYMENT;

-- ② 资源：预期 2 行 —— 一个 .bpmn20.xml，一个 .png（GENERATED_=1 表示引擎自动生成的流程图）
SELECT ID_, NAME_, GENERATED_, DEPLOYMENT_ID_ FROM ACT_GE_BYTEARRAY;

-- ③ 流程定义：预期 1 行，VERSION_=1，SUSPENSION_STATE_=1（1=激活，2=挂起）
SELECT ID_, KEY_, NAME_, VERSION_, SUSPENSION_STATE_, DEPLOYMENT_ID_ FROM ACT_RE_PROCDEF;
```

**关键点**：
- 表②出现 **2 行**是正常的——一行是你传的 XML 原文，另一行是引擎按 BPMN 里的 DI 坐标**自动画的 png 流程图**（`GENERATED_=1`）。这也是为什么模板里要保留那段 `bpmndi:BPMNDiagram` 坐标。
- 三张表的 `DEPLOYMENT_ID_` 应都指向表①那一行的 `ID_`，三者是"一次部署"绑在一起的。

---

## 四、步骤 2 · 分页列表

**目的**：验证 `page` 接口把定义装进和用户列表一致的 `PageResult` 外壳。

`GET /process-definition/page?current=1&size=10&latestOnly=false`

**预期**：`records` 1 条、`total` 1；`records[0].key = leaveProcess`、`version = 1`。

> `latestOnly` 的区别等步骤 3 升版后才看得出来，先记住这里是 `false`（看全部版本）。

---

## 五、步骤 3 · 重复部署 → 验证版本机制

**目的**：Flowable 的核心特性——**同 key 再部署 = 自动升一个版本，老版本不动**。这是流程"改版但历史实例仍按旧版跑"的基础。

1. **再传一次同一个 `leave.bpmn20.xml`**（接口、参数完全一样）。
2. **看响应**：`version` 应变成 **2**，`id` 变成 `leaveProcess:2:xxxx`，`deploymentId` 是**新的一串**。
3. **复查表**：
   - `ACT_RE_DEPLOYMENT` → 现在 **2 行**（两次部署）
   - `ACT_RE_PROCDEF` → 现在 **2 行**，`VERSION_` 分别是 1 和 2，key 都是 `leaveProcess`
4. **再查 page 两种模式对比**：
   - `latestOnly=false` → **2 条**（v1 + v2 都在）
   - `latestOnly=true` → **1 条**（只留 v2 最新版）
   - 这一 2 一 1，就是 `latestOnly` 生效的证据。

---

## 六、步骤 4 · 挂起 / 激活

**目的**：验证挂起只改状态位、且防重复调用；挂起后新实例发不起来（和 Day 12 的"挂起时发起报错"呼应）。

用**最新版 v2 的 definitionId**（三段式 `leaveProcess:2:xxx`，**不是** key、也不是 deploymentId）：

1. `PUT /process-definition/{v2的definitionId}/suspend` → 成功。

```sql
SELECT KEY_, VERSION_, SUSPENSION_STATE_ FROM ACT_RE_PROCDEF WHERE VERSION_ = 2;
-- 预期 SUSPENSION_STATE_ 从 1 变成 2
```

2. **再挂起一次同一个** → 预期业务错误「流程定义已处于挂起状态」（`def.isSuspended()` 防重复分支）。
3. `PUT /process-definition/{v2的definitionId}/activate` → 成功，`SUSPENSION_STATE_` 变回 1。
4. **再激活一次** → 「流程定义已处于激活状态」。
5. **传错 id 测异常**：拿 `key`（`leaveProcess`）而不是三段式 id 去 suspend → 「流程定义不存在」（提醒你这里必须用完整 definitionId）。

> ⚠️ 若想接着走 Day 12，**最后记得让 v2 停在激活状态**，否则发起会被"已挂起"拦下。

---

## 七、步骤 5 · 删除部署

**目的**：验证按 **deploymentId**（不是 definitionId）删除，三张表连带清除。这里**先只测"无在途实例"的简单场景**；`cascade=false` 撞上在途实例的冲突分支，留到 **Day 12 有实例之后**再补（排期里那笔欠账）。

1. 挑 **v2 的 deploymentId**（步骤 3 响应里那串），`DELETE /process-definition/deployment/{v2的deploymentId}?cascade=false` → 成功（此刻还没发起过任何实例，删得掉）。
2. **复查**：v2 相关的行在三张表里全消失——

```sql
SELECT * FROM ACT_RE_PROCDEF WHERE VERSION_ = 2;                          -- 应 0 行
SELECT * FROM ACT_RE_DEPLOYMENT WHERE ID_ = '{v2的deploymentId}';          -- 应 0 行
SELECT * FROM ACT_GE_BYTEARRAY WHERE DEPLOYMENT_ID_ = '{v2的deploymentId}'; -- 应 0 行
```

而 **v1 仍在**（删除是按部署粒度，不影响别的部署）。

3. **传错 id 测异常**：拿一个不存在的 deploymentId 删 → 「部署不存在」。

---

## 八、收尾：给 Day 12 留好现场

删完 v2 后，库里应还剩 **v1 一条激活的 `leaveProcess` 定义**。这正是 Day 12 需要的起点。确认一下：

```sql
SELECT KEY_, VERSION_, SUSPENSION_STATE_ FROM ACT_RE_PROCDEF;
-- 预期：leaveProcess, 1, 1（一条、v1、激活）
```

若把 v1 也误删光了，重新 deploy 一次 `leave.bpmn20.xml` 补回来即可。

然后去 `04-验证清单.md` 逐项打勾，疑问记进 `05-疑问与解答.md`。

---

## 九、最容易踩的点

1. **deploymentId ≠ definitionId**：删除用 **deploymentId**（一串纯数字/字母），挂起激活用 **definitionId**（三段式 `key:version:序号`）。接反了就报"不存在"。
2. **deploy 是 multipart 不是 JSON**：knife4j 里这个接口会显示文件选择框，别当成 body 贴 XML。
3. **文件名后缀**必须 `.bpmn20.xml` 或 `.bpmn`，否则接口层直接 400（引擎对别的后缀会"存了但不解析"，代码提前拦了这个坑）。
4. **cascade 冲突分支这次测不到**是对的——现在没有在途实例。它排在 Day 12 步骤 5，等发起实例后再回来触发。
