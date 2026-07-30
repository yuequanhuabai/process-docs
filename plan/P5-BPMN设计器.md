# P5 · BPMN 设计器（Day 19–22）

> 状态：**⬜ 未开始** ｜ 端：前端 ｜ 主题：bpmn-js 预览/编辑 + 属性面板 + 整合部署
> 返回 [总控进度](../05-重写排期计划.md) ｜ 当前位置见 [测试进度断点](../测试进度断点.md)

> ⚠️ **本阶段是全项目最难的一块**，单列 4 天、排在四个表格页热手之后。风险缓解：先 Viewer 再编辑，分步推进。
> 依赖：`bpmn-js 18`（已在技术选型内）。后端 `deploy` 接口已就绪（P3 Day 11），本阶段不用改后端。

---

## 一、任务清单

**Day 19 · 前端：设计器入口 + bpmn-js 预览**　⬜
- [ ] `views/designer` 设计器列表页（原纵切版 Day 12 的入口壳挪到此处）
- [ ] `components/BpmnDesigner/index.vue` + `BpmnViewer.vue`，加载并渲染 BPMN
- [ ] **验收**：能把一份 BPMN XML 渲染成流程图

**Day 20 · 前端：BpmnDesigner 编辑 + flowable 扩展**　⬜
- [ ] `toolbar.vue`（新建/保存/缩放/导出 XML）+ `FlowableModdle.json`（flowable 命名空间属性扩展）
- [ ] **验收**：拖节点画简单流程并导出带 flowable 属性的 XML

**Day 21 · 前端：PropertiesPanel 属性面板**　⬜
- [ ] `PropertiesPanel/index` + 子面板：Process / StartEvent / UserTask / SequenceFlow / Common
- [ ] **验收**：选中节点改名称/办理人等属性并写回 XML

**Day 22 · 前端：编辑器整合 + 部署联调**　⬜
- [ ] `views/designer/editor` 整页（设计器 + 属性面板）+ 保存调后端部署（bpmn-js `saveXML()` 得到字符串，包成 Blob 当文件传 multipart，deploy 接口不用改）
- [ ] **验收**：设计 → 保存 → 部署端到端通，`process` 列表能看到新流程。**P5 关闭**

---

## 二、打卡记录

| Day | 主题 | 端 | 实际完成度 | 受阻/备注 |
|-----|------|----|-----------|-----------|
| 19 | 设计器入口+bpmn-js 预览 | 前 | | |
| 20 | BpmnDesigner 编辑 | 前 | | |
| 21 | PropertiesPanel | 前 | | |
| 22 | 编辑器整合部署 | 前 | | |

---

## 三、开工前的现成弹药

- **模板 BPMN**：`process-back/src/main/resources/processes/leave.bpmn20.xml` 含完整 DI 坐标，可直接喂给 bpmn-js 渲染。
- **图路径高亮的数据来源**：P3 Day 14 决策2 定了后端 `activities()` **不过滤 `sequenceFlow`**，返回的连线 id 正好给这里做路径高亮用（一份数据两用）。
- **部署接口**：`POST /process-definition/deploy`（multipart），P4 的 `api/process.ts` 里特意把 `deploy` 留空给本阶段接。
