# 泛型化的 `toPage()` 与 Flowable 的自限定泛型

> **触发点**（2026-07-31）：读 `process_instance/09-Day16-完整代码.md` 里改造后的 `toPage()` 时问——
> "`private <E> IPage<ProcessInstanceVO> toPage(Query<?, E> query, Function<E, ProcessInstanceVO> mapper, long current, long size)`，可以帮我解析一下吗？"
>
> 本篇拆两件事：① 这个方法**做什么**（分页收尾，逻辑一行没变）；② 那串泛型**为什么必须存在**（它解决的是两个具体的编译期障碍，不是为了好看）。

---

## 一、先纠一个误解

> ❌ "泛型化是为了代码更优雅 / 少写几行。"

不是。它解决的是**两个会让编译器直接报红的硬障碍**，不通过重构手法就绕不过去：

1. `ProcessInstanceQuery` 与 `HistoricProcessInstanceQuery` **没有继承关系**（是平级兄弟），旧的写死参数版一个字都塞不进去；
2. 在类型未知的方法体里，**重载决议无法进行**——`ProcessInstanceVO.of` 有两个重载，编译器不知道该选哪个。

"少一份重复代码"是顺带的收益。如果只图这个，`09` 文末给的 `toHiPage` 复制版完全够用，可读性还更好。**先认清它在解决什么，才知道什么时候不该用它。**

---

## 二、机制拆解（纵向剥层）

### 2.1 body 其实一行没变

对照你已提交的旧版（`ProcessInstanceServiceImpl.java:93-99`）：

```java
// 旧版：参数类型写死
private IPage<ProcessInstanceVO> toPage(ProcessInstanceQuery query, long current, long size) {
    long total = query.count();
    List<ProcessInstance> instances = query.listPage((int) ((current - 1) * size), (int) size);
    Page<ProcessInstanceVO> page = new Page<>(current, size, total);
    page.setRecords(instances.stream().map(ProcessInstanceVO::of).toList());
    return page;
}
```

```java
// 新版：只改了两处——参数类型、转换函数的来源
private <E> IPage<ProcessInstanceVO> toPage(Query<?, E> query,
                                            Function<E, ProcessInstanceVO> mapper,
                                            long current, long size) {
    long total = query.count();
    List<E> list = query.listPage((int) ((current - 1) * size), (int) size);
    Page<ProcessInstanceVO> page = new Page<>(current, size, total);
    page.setRecords(list.stream().map(mapper).toList());
    enrich(page.getRecords());          // Day 16 新增
    return page;
}
```

四步骨架完全一致：

| 步骤 | 干什么 | 落到 SQL |
|---|---|---|
| `query.count()` | 问总数 | `SELECT COUNT(*) FROM ACT_HI_PROCINST WHERE START_USER_ID_=?` |
| `query.listPage(offset, limit)` | 取当前页 | 同样的 WHERE + 分页（SQL Server 方言：`OFFSET ? ROWS FETCH NEXT ? ROWS ONLY`） |
| `new Page<>(current, size, total)` | 造 MP 外壳 | 无 SQL，纯对象 |
| `setRecords(...map(mapper)...)` | 引擎对象 → VO | 无 SQL |

⚠️ `(current - 1) * size`：前端传的是**页码**（第 1 页、第 2 页），`listPage` 吃的是**偏移量**（跳过几条）。第 1 页跳 0 条、第 2 页跳 `size` 条。分页 API 的 off-by-one 基本都出在这个换算上。

### 2.2 `Query<?, E>` 怎么读

`javap` 出来的接口原型（`flowable-engine-common-api-7.1.0.jar`）：

```java
public interface org.flowable.common.engine.api.query.Query<T extends Query<?, ?>, U> {
    T asc();
    T desc();
    T orderBy(QueryProperty);
    T orderBy(QueryProperty, Query$NullHandlingOnOrder);
    long count();
    U singleResult();
    List<U> list();
    List<U> listPage(int, int);
}
```

两个类型参数分工完全不同：

- **`U` = 查出来的元素类型**。决定 `list()` / `listPage()` 返回什么。
- **`T` = 自己的类型**——注意约束是 `T extends Query<?, ?>`，一个**指向自身**的类型参数。

两个实现（均已 javap 核实）：

```java
public interface ProcessInstanceQuery
        extends Query<ProcessInstanceQuery, ProcessInstance> { ... }

public interface HistoricProcessInstanceQuery
        extends Query<HistoricProcessInstanceQuery, HistoricProcessInstance>,
                DeleteQuery<...>, BatchDeleteQuery<...> { ... }
```

**关键：它俩之间没有任何继承关系。** 共同祖先只有 `Query`。这就是旧版塞不进去的根本原因。

### 2.3 `T` 是干嘛的——自限定泛型

`T` 叫**自限定泛型**（F-bounded polymorphism，俗称 CRTP）。它存在的唯一理由是**让链式调用穿过继承边界**：

```java
historyService.createHistoricProcessInstanceQuery()
        .startedBy("3")
        .desc()          // ← 关键在这
        .unfinished();   // 还能接着调 HI 专属方法
```

`desc()` 声明在**公共父接口** `Query` 上。如果它的返回类型写成 `Query`，那 `.desc()` 之后你就**只剩父接口那 8 个方法**，`.unfinished()` 当场编译不过。

声明成 `T`，而子接口把 `T` 钉死成自己（`Query<HistoricProcessInstanceQuery, ...>`），于是 `desc()` 返回的仍是 `HistoricProcessInstanceQuery`，链子能一路接下去。

> **后端视角类比**：这和 Java 自己的 `Enum<E extends Enum<E>>`、`Comparable<T>` 上的自引用是同一个模式。你天天写的枚举，声明就是 `class Color extends Enum<Color>`——同一手法。

**回到我们的签名**：`Query<?, E>` 第一个位置写 `?`，是在说「T 是什么我不关心」。因为方法体里只用 `count()` 和 `listPage()`，这两个方法的签名**不涉及 T**。只有 `E` 要用，所以只有它需要名字。

### 2.4 为什么必须**传** `Function`

这是"为什么必须长这个形状"的答案，也是最容易被跳过的一层。

试着把 `mapper` 参数删掉，在方法体里直接写：

```java
page.setRecords(list.stream().map(ProcessInstanceVO::of).toList());   // ❌ 编译不过
```

编译器会拒绝。原因：此刻 `E` 是**未知类型**——可能是 `ProcessInstance`，也可能是 `HistoricProcessInstance`。而 `of` 有两个重载。**重载决议发生在编译期、靠静态类型；`E` 在方法体内没有静态类型可用**，编译器无从选择。

而**调用方是知道的**。`page()` 里 `query` 明明白白是 `ProcessInstanceQuery`，编译器在调用点就能定下 `E = ProcessInstance`，选中 `of(ProcessInstance)`，把**选好的那个函数**打包成 `Function` 传进来。

> 一句话：**把「选哪个重载」这个决定，从不知情的方法体里，挪到知情的调用点。** 这就是传函数的全部意义。

### 2.5 推断的次序（不能颠倒）

```java
return toPage(query, ProcessInstanceVO::of, current, size);
```

1. `ProcessInstanceVO::of` 是**不精确方法引用**（有重载），按 JLS 18.5.1 它**不参与适用性推断**——先被搁置；
2. 于是 `E` **只由 `query` 实参决定** → `E = ProcessInstance`；
3. `E` 定了，目标类型 `Function<ProcessInstance, ProcessInstanceVO>` 才回过头来选中 `of(ProcessInstance)`。

**先定 E、再选重载**。反过来做不到——这也解释了为什么 2.4 里那种写法必然失败：没有 `query` 之外的信息源能定住 `E`。

---

## 三、诞生背景（横向讲史）

### 旧世界

参数写死 `ProcessInstanceQuery`，`page()` 和 `myStarted()` 共用一份，岁月静好（Day 11–12 的状态）。

### 痛点

Day 16 要把 `myStarted()` 改查历史表，拿到的是 `HistoricProcessInstanceQuery`。而 2.2 已经说明：**两者没有继承关系**。旧 `toPage` 一个字都塞不进去。

三条路：

| 方案 | 代价 |
|---|---|
| (a) 复制一份 `toHiPage`，参数写死 | 分页收尾逻辑存两份，`enrich()` 要记得两处都调，改一处忘一处 |
| (b) 重载 `toPage(HistoricProcessInstanceQuery, ...)` | 同上，body 仍是两份，只是名字统一了 |
| (c) 泛型化 | body 一份 |

### 新方案

找到两者的**最小公共父接口** `Query`，把「变的部分」（元素类型 `E`、转换函数 `mapper`）参数化，「不变的部分」（count → listPage → 装 Page → enrich）留在方法体里。

标准的提取公共逻辑动作，只是这次公共父类型藏在第三方 jar 里，得先 `javap` 才找得到。

### 代价（不是免费的，三笔）

1. **可读性**。`Query<?, E>` 叠加自限定泛型，不解释一遍确实劝退。这正是 `09` 文末留 `toHiPage` 替代写法的原因：**先跑通比先优雅重要**。
2. **失去对具体类型的访问**（真正的代价）。方法体内只剩 `Query` 那 8 个方法，再也调不到 `.processDefinitionKey()` 之类。这是抽象的固有代价——**抽到公共层，就只剩公共能力**。今天够用；哪天需要在 `toPage` 里碰具体查询条件，就得推翻重来。
3. 多一层 `Function` 间接调用。性能上可忽略，列出来只为完整。

---

## 四、动手实验

### 实验 1 · 证明 `Stream.toList()` 返回不可变 List（有对照组）

```java
List<String> a = Stream.of("x").collect(Collectors.toList());
a.set(0, "y");                      // ✅ 正常
List<String> b = Stream.of("x").toList();
b.set(0, "y");                      // ❌ UnsupportedOperationException
```

`Stream.toList()` 是 JDK 16 加的，和老写法 `collect(Collectors.toList())` 的关键差别就在这。**为什么要关心**见第五节坑 1。

### 实验 2 · 证明自限定泛型 `T` 不是摆设

在 `myStarted()` 里临时改一行：

```java
Query<?, HistoricProcessInstance> q =
        historyService.createHistoricProcessInstanceQuery().startedBy("3");
q.unfinished();   // ❌ 编译不过：Query 接口上没有这个方法
```

把变量类型换回 `HistoricProcessInstanceQuery`，立刻转绿。**这个红叉就是 `T` 存在的全部理由**，一眼看得见。

### 实验 3 · 证明为什么必须传 `Function`

把 `mapper` 参数删掉，在 body 里直接写 `.map(ProcessInstanceVO::of)`。编译器报 `cannot infer type` / `no suitable method found`——因为 `E` 未知。**这个红叉是 2.4 那段话的实证。**

### 实验 4 · 看清两条 SQL

`application.yml` 开 Druid SQL 日志，调一次 `my-started`，数一数：会看到 **`COUNT(*)` 和分页查询是两条独立的 SQL**。这直接引出第五节坑 2。

---

## 五、踩坑清单（都不在代码注释里）

### 坑 1 · `Stream.toList()` 不可变，`enrich()` 只是碰巧安全

`page.setRecords(...)` 存进去的是不可变 List（`setRecords` 只保存引用，不复制）。

当前安全，因为 `enrich()` 只调元素的 setter（改**对象内部**），没有 add/remove（改**列表结构**）。但哪天想在 `enrich` 里加一句 `records.removeIf(...)` 做过滤，当场 `UnsupportedOperationException`。

### 坑 2 · `count()` 与 `listPage()` 是两条独立 SQL，不在同一事务

两次查询之间，别人可能刚发起或办结了一个实例 → `total` 与 `records` 对不上。典型表现是**翻到最后一页发现是空的**。

Flowable 分页 API 天生如此，业务上一般接受，但要知道**这不是 bug**。

### 坑 3 · `(int)` 强转的括号位置

`current` / `size` 是 `long`，`listPage` 吃 `int`。`(int)((current - 1) * size)` 是对的——**先算完再转**。理论上深翻页超 21 亿会溢出，现实到不了。

### 坑 4 · `enrich(page.getRecords())` 与 `enrich(list)` 等价

`setRecords` 只存引用，`getRecords()` 拿回同一个对象。写成前者是为了表达「回填的是最终要返回的那批」，读起来意图更清楚，**不是**什么必要的写法。

### 坑 5 · javap 时方法常常"找不到"

- `count()` / `listPage()` **不在** `ProcessInstanceQuery` 或 `HistoricProcessInstanceQuery` 上，在公共父接口 `Query` 上；
- `processInstanceIdIn(Collection<String>)` **不在** `TaskQuery` 上，在父接口 `TaskInfoQuery` 上（而 `TaskInfoQuery<T, V> extends Query<T, V>`，同一套自限定模式）。

直接 javap 子接口找不到就以为方法不存在，是本项目已经踩过一次的坑。**javap 子接口看不到，就往父接口翻。**

---

## 六、常见误解速查表

| 误解 | 实际 |
|---|---|
| 泛型化是为了优雅/少写代码 | 是为了绕开两个编译期硬障碍（无继承关系 + 重载无法决议）；省代码是顺带的 |
| `Query<?, E>` 的 `?` 是随便写的 | 是明确表态「T 与本方法无关」。因为 `count`/`listPage` 的签名不涉及 T |
| 自限定泛型 `T extends Query<?,?>` 是过度设计 | 没它，`.desc()` 之后就调不到子接口专属方法，整条链断在中间 |
| 可以在泛型方法体里直接写 `ProcessInstanceVO::of` | 不行。`E` 未知 → 重载无法决议。必须由知情的调用点传进来 |
| `Stream.toList()` 和 `collect(Collectors.toList())` 一样 | 前者**不可变**，后者可变 `ArrayList` |
| `count()` 和 `listPage()` 是一次查询 | 两条独立 SQL，不在同一事务，翻页可能对不上 |
| `page()` 是"零改动" | 查询逻辑没改，但 `toPage` 变 4 参后 return 行必须补 mapper，否则编译不过 |

---

## 七、回到本项目

| 位置 | 状态 |
|---|---|
| `process-back/.../ProcessInstanceServiceImpl.java:93-99` | **当前仍是旧版 3 参 `toPage`**（写死 `ProcessInstanceQuery`），Day 16 待改造 |
| `process-back/.../ProcessInstanceServiceImpl.java:72-77` | `myStarted()` 仍查 RuntimeService，Day 16 待改 HI |
| `process-back/.../ProcessInstanceVO.java:77-97` | `of(HistoricProcessInstance)` + `statusOf()` **已提交**（commit `5dabc3b`），VO 侧已就位 |
| `process-docs/process-back/process_instance/09-Day16-完整代码.md` §3 | 泛型版参考代码 + 文末 `toHiPage` 替代写法 |
| `process-docs/process-back/process_instance/08-Day16-操作步骤.md` Step 4 | 引导版（自己写时看这篇） |

**2026-07-31 的教训留档**：`09` 里这一段最初写成 `return  (query, ProcessInstanceVO::of, current, size);`——**漏了方法名 `toPage`**，且 `08`/`09` 两处散文都写着「`page()` 零改动」，与实际矛盾。根因是「标完整代码的文档从没进过编译器」。已修，并确立流程：**参考代码先落进真实项目 `mvn compile` 过一遍，再复制进文档。**

---

## 八、一句话总结

`toPage` 的分页逻辑一行没变，变的只是**「谁来决定元素类型」**——旧版由方法自己写死，新版交给调用方，靠 `E` 和 `Function` 这一对把决定权传进来；代价是方法体内从此只看得见 `Query` 的公共能力。

---

## 九、往下可以再挖的

- **MyBatis-Plus 的 `IPage` / `Page` 为什么分接口与实现**，`PageResult` 又是在哪一层拆给前端的（前后端契约在 P0–P3 固化，可回看）
- **Flowable 的 `listPage` 在 SQL Server 方言下究竟生成什么**——方言配置能在 `ACT_GE_PROPERTY` 里看到
- **自限定泛型在 JDK 自身 API 的经典案例**：`Enum<E extends Enum<E>>`，顺带解释为什么 `Enum` 不能被手动继承
- **`Query` 家族的第二条继承线**：`HistoricProcessInstanceQuery` 还实现了 `DeleteQuery` / `BatchDeleteQuery`，那是批量删历史的入口——与 `cascade=true` 删部署抹除审计线索是同一片区域
