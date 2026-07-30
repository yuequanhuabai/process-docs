# Flowable 工作流重写 · 文档仓库

> 本仓库是整个项目的**唯一文档来源**。代码仓库（`process-back` / `process-front`）里不再放文档。
>
> 配套代码：`process-back`（Spring Boot 3.3 + Flowable 7.1 + MyBatis-Plus + SQL Server）、`process-front`（Vue 3.5 + TS + Vite + Element Plus）。

---

## 开场读什么

**只读这两个就够定位：**

| 顺序 | 文档 | 作用 |
|---|---|---|
| 1 | [`测试进度断点.md`](./测试进度断点.md) | ★ **当前在哪、下一步做什么、数据库现场**。进度以此为准 |
| 2 | `plan/` 里**当前阶段**那一篇 | 该阶段的每日任务与打卡（现在是 [`plan/P4`](./plan/P4-业务前端批量.md)）|

其余的按需查，不要开场通读。

---

## 目录结构

```
process-docs/
├─ README.md                    ← 本文
│
├─ 双CLI工作流.md                协作总纲：两个 CLI 怎么分工
├─ 问答CLI起手提示词.md          开答疑 CLI 时整体粘贴这段
├─ 讲解规则.md                   讲解风格：纵向剥层 + 横向讲史 + 动手实验
│
├─ 测试进度断点.md          ★ 进度书签（最勤更新，冲突时以它为准）
├─ 05-重写排期计划.md       ★ 主线总控：阶段总览 + 技术栈 + ⚠️ 挂起项总表
├─ plan/ P0–P8.md           ★ 各阶段的每日任务与打卡记录
├─ 变更日志.md                   历次产出流水账 + 已消化归档（只追加，开场不读）
│
├─ process-back/                 后端文档
│   ├─ 00-领域概念与术语表.md
│   ├─ 01-宏观架构.md
│   ├─ 02-技术选型与可替代方案.md
│   ├─ 03-模块功能定位.md
│   ├─ 04-后端改造步骤.md
│   ├─ 重写分析维度参考.md
│   ├─ process_deploy/           流程定义与部署（Day 11）
│   ├─ process_instance/         流程实例（Day 12 + Day 16 改造）
│   ├─ process_task/             待办任务（Day 13）
│   ├─ process_history/          历史查询（Day 14）
│   └─ deep_dive/                学习笔记：历史表族深挖、待深入主题清单
│
├─ process-front/                前端文档
│   ├─ process_manage/           流程管理页（Day 15）
│   ├─ process_instance/         实例 + 我的发起（Day 16）
│   ├─ 前端答疑/                 通用 Vue 原理笔记（11 篇，见 索引.md）
│   ├─ UI-配色规律与深色侧栏方案.md
│   └─ 2026-07-03-Day4联调排错与CORS实验笔记.md
│
└─ tools/
    └─ check-links.sh            文档死链检查器
```

---

## 三类文档，别混用

| 类型 | 是什么 | 在哪 | 更新频率 |
|---|---|---|---|
| **主线** | 排期、阶段任务、当前进度 | 仓库根 + `plan/` | 每天 |
| **落地手册** | 某一天具体怎么做、验收清单、FAQ | `process-back/process_*/`、`process-front/process_*/` | 做那一天时写一次 |
| **学习笔记** | 原理剥层、踩坑沉淀，与进度无关 | `process-back/deep_dive/`、`process-front/前端答疑/` | 有疑问时随时加 |

**跨端的任务（如 Day 16）按端拆两篇**，各放各家，主线的 `plan/P*.md` 同时链到两篇 —— 不要在前端文档里写后端改造。

---

## 维护约定

- **每天收工**：填当前阶段 `plan/P*.md` 的打卡行 + 更新 `测试进度断点.md`
- **阶段切换**：改 `05-重写排期计划.md` 第一节总览表的状态列（只有这一处要动总控）
- **新产出 / 新决策**：追加进 `变更日志.md`，别往断点文档堆（那份刻意压着不让它膨胀）
- **新增挂起项**：在「对应 Day 条目 + 总控第四节总表 + `plan/P8` 第三节展开」**三处都登记**，否则拆开后会丢
- **改完目录结构或搬动文件**：跑一次死链检查

```bash
bash tools/check-links.sh          # 退出码 0 = 全通，1 = 有死链
bash tools/check-links.sh -v       # 连忽略掉的也列出来，排查误判用
```

---

## 仓库与分支

`core2` 本身不是 git 仓库，底下三个各自独立：

| 目录 | 仓库 | 分支约定 |
|---|---|---|
| `process-docs/` | `process-docs.git` | 本仓库，唯一文档来源 |
| `process-back/` | 后端代码 | **在 `dev` 开发** |
| `process-front/` | 前端代码 | **在 `dev` 开发** |

## 关于历史

本仓库的文档 2026-07-30 从 `process-back/docs/` 与 `process-front/docs/` 迁入，之后两个代码仓库**在 `dev` 分支上删除了 `docs/`**。

**`master` 分支保持不变，作为迁移前的完整快照**（`process-back/master` 48 篇、`process-front/master` 23 篇）以及那 68 条涉及 docs 的提交历史的归档。本仓库的修改历史从导入那一刻起算 —— 要查旧账：

```bash
git -C ../process-back  log master -- docs/<文件>
git -C ../process-front log master -- docs/<文件>
```

> 💡 统计中文文件名时注意：`git ls-files` / `ls-tree` 默认会把非 ASCII 路径转义并加引号，`grep '^docs/'` 这类锚点会失配。加 `-c core.quotePath=false` 才对。
