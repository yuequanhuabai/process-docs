# 08 · 回到 `toPage`（收官）

> **触发点**：`00` 定的目标是 **③ 能自己设计泛型**，验收标准是「**合上文档能写出来**」。本篇就是那场考试。
> 另外还欠 `00` 承诺的一条纪律：**什么时候不该写泛型**。`06` §6.2 预演了一半，这里结账。
>
> **本篇写完，泛型系列收官，回主线做 Day 16 第 2–6 项。**

---

## 一、先闭卷考一次（别往下翻）

> ⚠️ **认真做这一节，它是整个系列唯一的验收动作。**
> 三道题递进，全部**合上前七篇**，纸笔或 IDE 都行。做完再看第二节。

### 第 1 题 · 从零写出 `R<T>`（目标 ③ 的及格线）

不看 `R.java`，写一个统一响应包装类，要求：

- 有 `code` / `msg` / `data` 三个字段，`data` 的类型由使用方决定
- 有一个静态方法 `ok(data)`，返回装好 data 的实例
- 有一个静态方法 `fail(msg)`，不带 data

**写完自己检查三件事**：`<T>` 写在哪几个位置？为什么 `ok` 前面必须有 `<T>`？`fail` 那个 `<T>` 是从哪来的？

### 第 2 题 · 从零写出 `toPage`

**已知需求**（就这些，别的都不给）：

- `page()` 要查在途实例：`ProcessInstanceQuery` → 查出 `ProcessInstance`
- `myStarted()` 要查历史实例：`HistoricProcessInstanceQuery` → 查出 `HistoricProcessInstance`
- 两者都要：`count()` 拿总数、`listPage(offset, size)` 拿当前页、逐个转成 `ProcessInstanceVO`、装进 `IPage<ProcessInstanceVO>`
- 两个 Query 的公共父接口是 `Query<T extends Query<?,?>, U>`，`count()`/`listPage()` 都在它上面
- 转换逻辑不同：`ProcessInstanceVO.of` 有两个重载

**写出方法签名 + 方法体。** 卡住的话，按顺序问自己：

1. 需要几个类型参数？各代表什么？（`03` 的"这个类型后面还要提吗"）
2. 写类上还是方法上？（`04` 四问）
3. "转换逻辑不同"怎么变成参数？（`05` 后遗症 ①）
4. `Query` 的第一个参数位置填什么？（`06` 的 `?`）

### 第 3 题 · 三个判断（每题一句话说清"为什么"）

1. 下面两个方法能同时存在吗？
   ```java
   IPage<..> page(Query<?, ProcessInstance> q, long c, long s)
   IPage<..> page(Query<?, HistoricProcessInstance> q, long c, long s)
   ```
2. `toPage` 里能不能写 `if (e instanceof ProcessInstance)` 来省掉 `mapper` 参数？
3. `Query<?, E>` 里那个 `?` 换成 `T`（并在方法上声明 `<T extends Query<?,?>>`）会怎样？

---

## 二、`toPage` 是怎么"长"出来的（设计过程，不是解释结果）

> `06` §6.1 是**逐字符解释已有签名**。这一节反过来——**从需求一步步推出签名**。
> ③ 级的区别就在这里：读懂是"给你签名，你能拆"；设计是"给你需求，你能长出签名"。

### 第 0 步 · 先写最笨的版本

**任何泛型都不该一上来就写。先写出重复代码，让重复自己暴露出来。**

```java
private IPage<ProcessInstanceVO> toPage(ProcessInstanceQuery query, long current, long size) {
    long total = query.count();
    List<ProcessInstance> rows = query.listPage((int)((current-1)*size), (int)size);
    List<ProcessInstanceVO> vos = rows.stream().map(ProcessInstanceVO::of).toList();
    IPage<ProcessInstanceVO> page = new Page<>(current, size, total);
    page.setRecords(vos);
    return page;
}

private IPage<ProcessInstanceVO> toHiPage(HistoricProcessInstanceQuery query, long current, long size) {
    // ……和上面一模一样，只有两处不同
}
```

**盯住"只有两处不同"这句话**——泛型化的全部工作就是把这两处变成参数。

### 第 1 步 · 找出到底哪里不同

逐行对照，**只有两处**：

| # | 不同的地方 | `page()` 版 | `myStarted()` 版 |
|---|---|---|---|
| ① | query 的类型 | `ProcessInstanceQuery` | `HistoricProcessInstanceQuery` |
| ② | listPage 返回的元素类型 + 转换方法 | `ProcessInstance` → `of(ProcessInstance)` | `HistoricProcessInstance` → `of(HistoricProcessInstance)` |

**其余每一行字符级相同。** 这就是泛型化的正当理由——真有可复用的逻辑，不是硬凑。

### 第 2 步 · 逐个决定：起名字还是不起名字

**这是设计泛型最核心的一步**，判据来自 `03`/`06`：

> **这个类型，在签名或方法体的别处还要提到吗？要 → 起名；不要 → `?`。**

**① query 的类型：**

方法体里怎么用 query？只有 `query.count()` 和 `query.listPage(...)`——**两个都在父接口 `Query` 上**（`javap` 已验）。

从头到尾**没有任何地方需要知道它是哪种 Query**，也不需要它的返回值类型（不做链式调用）。

→ **不起名，用 `?`**

**② 元素类型：**

它出现在两处——`listPage()` 的返回元素、`mapper` 的入参。**要在别处提到 → 必须起名。**

→ **起名 `E`**（Element；叫 `T` 也行，见 `03`）

**这一步的产出：** `Query<?, E>`

> 💡 **很多人卡在这儿，是因为默认"能起名就起名"。** 反了——**起名字是有成本的**（读的人要一路跟踪它），只在真要用时才起。这条纪律第四节还会再出现。

### 第 3 步 · 处理"转换逻辑不同"

`toPage` 拿到一个 `E`，要变成 `ProcessInstanceVO`。它自己做得到吗？

- `new ProcessInstanceVO(e)`？→ 要知道 `e` 是哪种，才能挑对逻辑。**运行期 `E` 不存在**（`05` ①）
- `if (e instanceof ProcessInstance)`？→ 能编译，但那就等于泛型白写，退回 `01` 的手工分派

**所以只剩一条路：谁知道 `E` 是什么，谁负责提供转换逻辑——把"怎么转"当参数传进来。**

```java
Function<E, ProcessInstanceVO> mapper
//        ↑ 第二个位置不能写 R，R 是你的响应类（03 §3.3）
```

> **这一步是被擦除逼出来的，不是风格选择。** —— `07` §7.1 说的"擦除税"。

### 第 4 步 · 决定 `<E>` 写类上还是方法上

`04` 的四问：

| 问 | 答 |
|---|---|
| 有字段用 `E` 吗？ | 没有 |
| 是 static 吗？ | 不是 |
| 多个方法共享吗？ | 不，只有 `toPage` 自己用 |
| → | **方法上** |

### 成品

```java
private <E> IPage<ProcessInstanceVO> toPage(Query<?, E> query,
                                            Function<E, ProcessInstanceVO> mapper,
                                            long current, long size) {
    long total = query.count();
    List<E> rows = query.listPage((int)((current - 1) * size), (int)size);
    List<ProcessInstanceVO> vos = rows.stream().map(mapper).toList();
    IPage<ProcessInstanceVO> page = new Page<>(current, size, total);
    page.setRecords(enrich(vos));
    return page;
}
```

调用方：

```java
return toPage(query, ProcessInstanceVO::of, current, size);
//                   ↑ E 由 query 的实际类型推断，编译器据此在 of 的两个重载里选中正确的那个
```

> **四步走完，签名是"长"出来的，不是"想"出来的。** 每一步都有判据，没有一步靠灵感。
> **这就是 ③ 级的实质**——不是记住某个模板，是有一套能重复执行的决策流程。

---

## 三、第一节三道题的答案

<details>
<summary>第 1 题 · <code>R&lt;T&gt;</code></summary>

```java
public class R<T> {              // ← 类上：判据 1（有字段 data 要用）
    private int code;
    private String msg;
    private T data;

    public static <T> R<T> ok(T data) {    // ← 方法上：判据 2（static，没得选）
        R<T> r = new R<>();
        r.setCode(200); r.setData(data); r.setMsg("success");
        return r;
    }

    public static <T> R<T> fail(String msg) {   // ← 又是一个新的 T
        R<T> r = new R<>();
        r.setCode(500); r.setMsg(msg);
        return r;
    }
}
```

**三个自检：**
- `<T>` 出现在类声明、每个 static 方法声明——**类上 1 个 + 每个方法各 1 个，互不相干**（`03` 实验 3）
- `ok` 前面必须有 `<T>`，因为 static 方法拿不到实例的类型参数（`04` 判据 2）
- `fail` 那个 `<T>` **完全推不出来**（没有参数用到 T），只能靠**目标类型**：`R<String> r = R.fail("x")`（`04` 实验 3）
</details>

<details>
<summary>第 2 题 · <code>toPage</code></summary>

见第二节"成品"。**对照要点**（签名对上就算过）：

- 一个类型参数 `E`，不是两个
- `<E>` 在方法上不在类上
- `Query<?, E>`——第一个位置是 `?` 不是 `T`
- 有 `Function<E, ProcessInstanceVO>` 参数，第二个位置是具体类型不是 `R`
</details>

<details>
<summary>第 3 题 · 三个判断</summary>

**1. 不能。** 擦除后两个都是 `page(Query, long, long)`，name clash（`05` ④）。判据是**看擦除后的签名，不是你写的签名**。

**2. 能编译，但不该。** `instanceof ProcessInstance`（不带类型实参）是合法的。但这样一来 `toPage` 就得知道所有可能的 `E`，每加一种查询都要改它——**泛型本来就是为了消灭这种分派**。而且 `E` 就没必要存在了，直接收 `Object` 得了。

**3. 能编译，但没好处。** `toPage` 方法体从头到尾没提过 `T`，白多一个类型参数；调用方还得多推一个类型；读的人要多跟踪一个名字。**能用 `?` 就别起名字。**
</details>

---

## 四、⭐ 什么时候**不该**写泛型

> `00` 承诺的那条纪律：**会设计 ≠ 到处用。验收标准是"设计得出来，且知道什么时候不该设计"。**
> 刚学会泛型最典型的翻车，就是拿它去套本来两个普通方法就能解决的事。

### 4.1 五个"别写"的信号

| # | 信号 | 为什么 |
|---|---|---|
| ① | **只有一个调用点** | 泛型的收益来自"多个不同类型复用同一份逻辑"。只有一处 = 纯成本 |
| ② | **类型参数在方法体里只出现一次或零次** | 说明它不承载信息。用 `?`，或者干脆写具体类型 |
| ③ | **为了泛型化不得不新增参数** | `mapper` 就是新增的成本。**收益必须明显大于它** |
| ④ | **调用方必须显式写类型实参才能编译** | 推断不出来 = 抽象的形状错了。回去重想 |
| ⑤ | **需要 `@SuppressWarnings("unchecked")` 才能过** | 你在跟类型系统对着干。（自限定泛型是唯一常见例外，但那是**库作者**的活，见 4.3） |

### 4.2 三个"该写"的信号

| # | 信号 |
|---|---|
| ① | **两个以上真实存在的不同类型，逻辑逐行相同**（第二节第 1 步那张表就是证据） |
| ② | **类型参数在签名里出现 ≥ 2 次**——起名字有回报 |
| ③ | **不写泛型就只能复制粘贴，或退回 `Object` + 强转** |

### 4.3 收益门槛随「读者数量」变化 ⭐ 最容易被忽略的一条

同一个泛型技巧，值不值得写，**取决于有多少人要读它**：

| 谁写的 | 读者 | 值得上自限定泛型吗 |
|---|---|---|
| Flowable 的 `Query<T extends Query<?,?>, U>` | **几万个调用方** | ✅ 绝对值得。省下的样板代码乘以几万 |
| 你的 `toPage`（private，一个类里两个调用点） | **只有你** | 🔸 边界情况，见下 |

> **库作者和应用作者的判据不一样。** 库里多写一层抽象，成本由作者独担、收益被所有用户分享；应用里多写一层抽象，成本和收益都是你自己的。
>
> **别拿 Flowable 的写法当自己的标准。**

### 4.4 复盘：`toHiPage` 复制版其实是个正当选项

当初 `09` 文档给的替代方案：

> 保留原来吃 `ProcessInstanceQuery` 的 `toPage`，另复制一份 `toHiPage(HistoricProcessInstanceQuery, long, long)`，参数写死，两个方法末尾都调 `enrich()`。

**用 4.1/4.2 冷静评一遍：**

| 维度 | 泛型版 | 复制版 |
|---|---|---|
| 调用点数量 | 2 个 | 2 个 |
| 新增参数 | +1（`mapper`） | 0 |
| 重复代码 | 0 | 约 6 行 × 2 |
| 读者门槛 | 要懂 `?` + `Function` + 方法级泛型 | 会读 Java 就行 |
| 加第三种查询时 | 改 0 行 | 再复制一份 |

**结论：这是个真正的边界情况，两边都站得住。**

- **如果这是生产项目、deadline 在即、团队里有人不熟泛型 → 复制版是更好的工程选择**，6 行重复远比一个没人敢改的签名便宜
- **你选泛型版是因为学习目的**——「这个以后会经常遇到，是必须要过的一道关卡」

> ⚠️ **学习目的和工程目的是两回事，别混。**
> 学完之后回到日常开发，**默认应该是"不写泛型"，除非 4.2 的信号亮起来。**
> 「我刚学会所以到处用」是最典型的翻车方式——而且翻车的通常不是写的人，是三个月后来读的人。

---

## 五、验收：真的写进项目并编译通过

> ⚠️ 前面全是纸上。**这一步跑通，泛型这关才算过。**

1. 打开 `ProcessInstanceServiceImpl.java`
2. **合上所有文档**，按第二节的四步，把 `toPage` 改成泛型版
3. 改 `page()` 的 return 行补上 mapper（⚠️ **查询逻辑零改动 ≠ 整个方法零改动**，这是踩过的坑）
4. ```bash
   cd process-back && ./mvnw -q compile
   ```

**编译转绿 = 及格。**

**编译不过也别急着翻文档**，先看报错属于哪一类：

| 报错关键词 | 去查 |
|---|---|
| `cannot find symbol: method count()` | `06` §2.6——方法可能在父接口 `Query` 上 |
| `incompatible types` / `no suitable method` | `06` §2.1——`?` 相关的读写限制 |
| `name clash ... same erasure` | `05` ④ |
| `non-static type variable T` | `04` 判据 2 |
| `unexpected type / type parameter T` | `05` ①——你在试图 `new E()` |
| `no suitable method found for toPage(...)` | 大概率是漏了 mapper 参数（第 3 步） |

**能从报错反推到哪一篇，比一次写对更能说明你懂了。**

---

## 六、全系列速查（一页）

### 六把钥匙

| # | 钥匙 | 出处 |
|---|---|---|
| 1 | 泛型是**编译期的类型标注**，把运行期的 `ClassCastException` 提前到编译期 | `01` |
| 2 | **声明保留、实例不保留**——擦掉的是实例身上的类型实参，声明处的信息在 `Signature` 属性里 | `02` |
| 3 | `T` 不是"某种类型"，是**类型的变量**；读签名先分清**声明处 vs 使用处**，然后**代入真实类型** | `03` |
| 4 | `<T>` 写哪：**字段用吗 → static 吗 → 多方法共享吗 → 都不是就放方法上** | `04` |
| 5 | **运行期需要知道 `T` 吗？需要就不行**——六条后遗症一条模板推完 | `05` |
| 6 | `?` 是**匿名类型参数**（不起名因为不再提它）；`? extends` 只读、`? super` 只写 = **PECS** | `06` |

### 三条纪律

1. **能用 `?` 就别起名字**——起名有成本（`08` §2 第 2 步）
2. **先写重复代码，让重复自己暴露出来**，再决定要不要抽（`08` §2 第 0 步）
3. **默认不写泛型**，除非 4.2 的信号亮起（`08` §4）

### 四个最容易归错因的地方

| 现象 | ❌ 常见归因 | ✅ 真实原因 |
|---|---|---|
| `toPage` 里不能直接写 `::of` | 擦除 | **重载决议**（编译期），`02` §7.3 |
| static 用不了类上的 `T` | 擦除 | **作用域**（没有实例），`05` §二末尾 |
| `List<Object> l = stringList` 不行 | 擦除 | **泛型不变**，`05` §3.1 |
| `? extends` 不能 add | 语法限制 | **编译器不知道实际类型**，`06` §2.1 |

---

## 七、回到主线：Day 16 复工清单

泛型这关过了，主线可以接上。**按 `测试进度断点.md` 「一」的六项走：**

| # | 任务 | 状态 |
|---|---|---|
| 1 | `ProcessInstanceVO` 加 5 字段 + `of(HistoricProcessInstance)` + `statusOf()` | ✅ 已提交 `5dabc3b` |
| 2 | `myStarted()` 改查 `HistoricProcessInstanceQuery.startedBy()` | ⬜ **从这里开始** |
| 3 | `enrich()` 批量补发起人姓名（**别写成 N+1**） | ⬜ |
| 4 | `toPage()` 泛型化 | ⬜ ← **本篇第五节就是它** |
| 5 | 前端 `views/instance` + `views/myStart` + `api/instance.ts` | ⬜ |
| 6 | 2 条路由 + 2 个菜单项 | ⬜ |

**手册**：`process_instance/08-Day16-操作步骤.md`（步骤+坑）、`09-Day16-完整代码.md`（完整代码）。

**两个已知的坑**（都在 `08` 手册里）：

- `page()` 的 return 行必须补 mapper —— 查询逻辑零改动 ≠ 整个方法零改动
- `enrich()` 里 `Collectors.toMap` 的 **value 为 null 会直接 NPE**（走 `HashMap.merge`），`real_name` 可空，**种子数据三条都有姓名，自测踩不出来**

**开工前还要造样本**：库里一条实例都没有（07-30 清库）。用 employee 发几条，凑齐「停 managerApprove / 停 adminApprove / 已办结 / 已终止」四种。

---

## 八、一句话总结（全系列）

泛型是**编译期的类型标注**，Java 因为要兼容 1.4 的旧代码而选了**擦除**——"声明保留、实例不保留"这一条推出了后面所有别扭的地方。而 `toPage` 之所以让人卡住，不是因为它难，是因为它同时叠了三样东西：**方法级类型参数**（`04`）、**通配符**（`06`）、**函数参数**（`05` 逼出来的）。**三样拆开每样都不难，合起来的设计流程也只有四步**：写出重复代码 → 找出哪里不同 → 逐个决定起名还是 `?` → 决定写类上还是方法上。**但真正的毕业标志不是能写出这个签名，是知道 `toHiPage` 复制版也是个正当选项——会设计之后，默认仍然是不写。**

---

## 九、系列收尾 & 还留着的坑

**泛型系列 `00`–`08` 到此结束。** 目标 ③（能自己设计泛型）的验收动作在第一节和第五节，**跑完第五节的 `mvn compile` 再来划句号。**

### 还留在清单上的

| 主题 | 位置 |
|---|---|
| `Stream.toList()` 为什么是 Java 16、为什么不可变、`final` vs immutable | `待深入主题清单.md` 第 6 条 ⬜ |
| `hi_tables/05-外围四表.md` 收官 | 清单第 3 条 ⬜ |
| 旧的 `../泛型toPage与自限定泛型.md` | **现在可以读了**（当初标注"会劝退"，读完本系列刚好） |

### 泛型上还没挖的（都不影响日常）

- **捕获转换**：`capture of ? extends X` 报错的来源（`06` §八）
- **`Method.isBridge()`** 与 Spring 的 `BridgeMethodResolver`（`05` §八）
- **`@SafeVarargs` 与堆污染**（`05` §八）
- **Spring `ResolvableType` / `ParameterizedTypeReference`**——写通用 HTTP 客户端时会撞上（`07` §九）
- **Project Valhalla**：JEP 401 / 402（`07` §九）

> 这些全是"遇到再查"的东西。**日常写业务代码，六把钥匙 + 三条纪律够用了。**
