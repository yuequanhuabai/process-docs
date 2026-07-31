# 07 · 横向对比：C++ / C# / Kotlin / TypeScript

> **触发点**：`00` 第三节 Q4「是从 C++ 借来的吗」只给了一句话答案。
> 而 `02`、`05`、`06` 三篇里，"**又是兼容性逼的**"这句话已经出现了三次——本篇把四条不同的路并排摆开，看清 Java 到底站在哪、代价换来了什么。
>
> 本篇没有新语法要学，是**定位篇**。读完你会知道：那些别扭不是你理解力的问题，是一次二十年前的取舍。

---

## 一、先纠两个误解

### 误解 1 · 「Java 泛型是抄 C++ 模板的」

**概念同源，实现路线相反，而且 C++ 模板严格说不算泛型。**

- **同源**：两者的学术祖宗都是**参数化多态**（parametric polymorphism），源头在 ML / Haskell 一脉
- **相反**：C++ 模板是**编译期生成多份代码**，Java 是**擦成一份**
- **不算泛型**：C++ 模板本质是**带类型的宏展开**——它不检查你的类型参数满不满足要求，直接把代码抄一遍再编译，编不过才报错

第三条是最大的区别，2.1 详说。

### 误解 2 · 「C# 泛型更好，说明 Java 设计得烂」

**不是技术优劣，是约束不同。** 两条关键史实：

| | Java 5（2004） | C# 2.0（2005） |
|---|---|---|
| 生态年龄 | 已经跑了 **9 年**，海量 jar 在生产环境 | .NET 才 **3 年**，生态小 |
| 能改虚拟机吗 | **不能**（改了旧 class 文件跑不了） | **改了**。CLR 专门为泛型加了指令和元数据 |
| 硬约束 | 新旧代码必须能**混着跑**（`01` 篇的三条约束） | 允许一次破坏性升级 |

> **C# 那次改动的主导者是 Don Syme**（微软研究院，后来做了 F#）。他做的事情本质上是**说服 CLR 团队改虚拟机**——Java 团队当年连这个选项都没有。
>
> **换句话说**：C# 不是想得比 Java 深，是**入场早、包袱轻，敢动地基**。

---

## 二、纵向剥层：四条路各自怎么走

### 2.1 C++ 模板 —— 编译期生成多份

```cpp
template<typename T>
T maxOf(T a, T b) { return a > b ? a : b; }

maxOf(1, 2);        // 编译器生成一份 int 版本
maxOf(1.5, 2.5);    // 再生成一份 double 版本
```

编译产物里**真的有两个函数**，机器码完全独立。这叫 **monomorphization（单态化）**。

**好处：**
- **零抽象开销**。`vector<int>` 里就是一片连续的 int，没有装箱（对比 `05` 后遗症 ⑥）
- 能对基本类型特化、能内联、能针对每个类型做不同优化

**代价（三条，都很痛）：**

1. **代码膨胀**：用了 10 个类型就生成 10 份，二进制体积暴涨、指令缓存压力大
2. **鸭子类型 = 报错地狱**：`T` 上没有任何约束。`a > b` 能不能用，要等**实例化那一刻**才知道。传个没定义 `>` 的类型进去，报错会从模板内部层层展开，动辄几百行——这是 C++ 二十年的著名痛点，**直到 C++20 的 `concepts` 才补上"约束"这个概念**（相当于 Java 一开始就有的 `<T extends Comparable<T>>`）
3. **必须暴露实现**：模板代码得写在头文件里，因为编译单元要看得见完整定义才能实例化

> 💡 **对照 Java**：`<T extends Comparable<T>>` 这种边界，C++ 花了二十多年才追上。**Java 在"约束"这件事上一开始就是对的**，只是在"运行期保留"上让了步。

### 2.2 Java —— 擦除，一份代码

前六篇讲透了，一句话复述：

> 编译期检查 + 插 `checkcast`，运行期一份代码、类型实参不存在。

**唯一的好处（但足够决定一切）：新旧代码能混着跑。**

### 2.3 C# —— reified，运行期真的有类型

CLR 在**虚拟机层面**认识泛型：

```csharp
List<int>    // CLR 为值类型生成专门的代码，真的存 int，无装箱
List<string> // 引用类型共享同一份代码（因为引用都一样大）
```

**于是 `05` 那六条后遗症大半消失：**

```csharp
T Create<T>() where T : new() => new T();      // ✅ 能 new T()
T[] arr = new T[n];                            // ✅ 能 new T[]
if (o is List<string>) { ... }                 // ✅ 能 instanceof 带类型实参
void M(List<string> a); void M(List<int> a);   // ✅ 重载不撞车
Console.WriteLine(typeof(List<int>));          // ✅ 运行期拿得到完整类型
```

**代价：**
- **虚拟机必须改**——这是 Java 付不起的那笔钱
- 值类型每个都生成一份代码（局部 monomorphization），有代码膨胀，但比 C++ 可控

### 2.4 Kotlin —— 跑在 JVM 上，所以也擦除；但开了两个后门

Kotlin 编译成 JVM 字节码，**擦除是继承过来的，躲不掉**。它做的是两件补救：

**① `reified` + `inline`：局部恢复运行期类型**

```kotlin
inline fun <reified T> isOfType(x: Any): Boolean = x is T
//         ↑ inline：调用点整个展开
//                  ↑ reified：展开时把 T 替换成真实类型
```

原理很朴素：**`inline` 让编译器把函数体粘贴到调用点，粘贴时 `T` 已经确定了，直接写死具体类型。** 所以：

- 只对 `inline` 函数有效（必须能展开）
- **类上的类型参数不能 reified**（类不能 inline）

> 这不是真 reified，是**编译期的偷梁换柱**。但它治好了 Java 里最烦人的一类场景——`02` §7.2 那个 `new TypeReference<R<SysUserVO>>() {}`，Kotlin 里可以写成 `objectMapper.readValue<R<SysUserVO>>(json)`，干净得多。

**② declaration-site variance：`out` / `in`**

```kotlin
interface List<out T>      // out = 只产出 T → 天然协变
interface Consumer<in T>   // in  = 只消费 T → 天然逆变
```

声明时说一次，之后 `List<String>` **自动**是 `List<Any>` 的子类型，调用方一个符号不用写。

**对比 `06` §3.3 的那张表**——Java 因为不能改 `List<T>` 的既有声明，只能在每个使用点写 `? extends`。**Kotlin 是新语言，声明处随便改。**

### 2.5 TypeScript —— 擦得最彻底

TS 编译成 JS，**类型信息一个字都不剩**（不像 Java 还有个 `Signature` 属性）：

```typescript
function first<T>(list: T[]): T | undefined { return list[0]; }
```

编译产物：

```javascript
function first(list) { return list[0]; }
```

**没有 `checkcast`，没有 `Signature`，运行期零校验。** 所以：

- `05` 的六条后遗症在 TS 里**更严重**——连 `instanceof` 的部分能力都没有
- 但 TS 从没打算做运行期安全，它的定位就是"给 JS 加一层编译期检查"

> **你前端已经在用它了**：`process-front` 里 `PageResult<T>`、`api/process.ts` 的返回类型，全是编译完就消失的东西。
> `讲解规则.md` 里记的那条「删掉冒号及其后半段，剩下的就是合法 JS」，说的就是这件事。

---

## 三、一张表：`05` 的六条后遗症在各语言的存活情况

| 限制 | Java | C++ | C# | Kotlin | TS |
|---|---|---|---|---|---|
| 不能 `new T()` | ❌ 禁 | ✅ 能 | ✅ 能（`where T:new()`） | ❌ 禁（reified 也不行） | ❌ 禁 |
| 不能 `new T[]` | ❌ 禁 | ✅ 能 | ✅ 能 | 🔸 `reified` 时能 | ❌ 禁 |
| 不能 `instanceof T` | ❌ 禁 | ✅ 无此概念 | ✅ 能 | 🔸 `reified` 时能 | ❌ 更严重 |
| 重载擦除撞车 | ❌ 撞 | ✅ 不撞 | ✅ 不撞 | ❌ 撞（可用 `@JvmName` 绕） | ❌ 撞 |
| 基本类型要装箱 | ❌ 要 | ✅ 不要 | ✅ 不要 | ❌ 要 | — |
| 需要桥接方法 | ❌ 要 | ✅ 不要 | ✅ 不要 | ❌ 要 | ✅ 不要 |
| **协变怎么写** | 使用点 `? extends` | 无（模板不管这个） | 声明点 `out`/`in`（C# 4.0） | 声明点 `out`/`in` | 结构化类型，天然协变 |

**三个可以带走的观察：**

1. **Kotlin 那一列和 Java 几乎一样**——因为**限制来自 JVM，不来自语言**。换语言不换虚拟机，跑不掉。
2. **C# 那一列全绿**——代价是它改了虚拟机。
3. **C++ 全绿但代价在别处**——代码膨胀 + 二十年的报错地狱。**没有免费的午餐，只有换个地方付账。**

---

## 四、横向讲史：时间线

| 年份 | 事件 | 关键点 |
|---|---|---|
| 1990s | ML / Haskell | 参数化多态的学术源头 |
| 1990 | C++ 模板 | 走 monomorphization 路线 |
| 1996–98 | **Pizza → GJ**（Odersky、Wadler、Bracha、Stoutamire） | 论文标题就是纲领：***"Making the future safe for the past"*** |
| 1998 | Odersky 的 GJ 编译器**被 Sun 采纳为 javac** | 泛型的实现方案在这一刻就定了 |
| **2004** | **Java 5 / JSR 14** | 擦除。**因为 9 年生态不能破坏** |
| **2005** | **C# 2.0** | reified。**Don Syme 说服 CLR 团队改虚拟机** |
| 2004 | Odersky 发布 **Scala** | 同一个人，这次没有历史包袱 |
| 2010 | C# 4.0 加 `out`/`in` | 声明点型变 |
| 2016 | Kotlin 1.0 | JVM 上，擦除照旧；用 `reified`+`inline` 局部补救 |
| 2014– | **Project Valhalla** | 想给 Java 补上 specialized generics。**喊了十年还没进正式版** |

**这条线最该记住的一件事：**

> **Java 泛型的实现方案在 1998 年就定了，比 Java 5 发布早六年。**
> 定它的人（Odersky）后来自己去做了 Scala——**他比谁都清楚擦除的代价，但在 Sun 的约束下那是唯一可行的方案。**

---

## 五、动手实验

> 本篇没法让你现装 C++/C#/Kotlin。**实验换个方向：用 Java 手工模拟 reified，看看要付多少代价。**
> 而这个"模拟"正是实战里最常用的绕法，比看别的语言有用得多。

### 实验 1 · `Class<T>` token —— Java 里手工 reify 的标准做法 ⭐⭐ 本篇最实用

**问题**：想写一个 `create()` 方法，返回 `T` 的新实例。`05` 后遗症 ① 说不行——运行期 `T` 不存在。

**解法**：**既然运行期没有，那就自己把类型当参数传进去。**

```java
import java.util.*;
public class X1 {
    // ❌ 做不到
    // static <T> T create() { return new T(); }

    // ✅ 把类型当成一个「值」传进来
    static <T> T create(Class<T> type) throws Exception {
        return type.getDeclaredConstructor().newInstance();
    }

    public static void main(String[] args) throws Exception {
        ArrayList<String> a = create(ArrayList.class);   // 返回类型自动是 ArrayList
        StringBuilder     b = create(StringBuilder.class);
        System.out.println(a.getClass() + " / " + b.getClass());
    }
}
```

**关键在 `Class<T>` 这个类型**：`ArrayList.class` 的类型是 `Class<ArrayList>`，所以传进去时编译器就把 `T` 推成了 `ArrayList`——**类型信息从"泛型"降级成了"一个普通参数"，于是穿透了擦除。**

> **这一招你项目里已经在用了**，只是没注意：
>
> | 位置 | 代码 |
> |---|---|
> | `JwtUtil.java:44` | `claims.get("username", String.class)` ← JJWT 的 `<T> T get(String, Class<T>)` |
> | `ProcessBackApplication.java:12` | `SpringApplication.run(ProcessBackApplication.class, args)` |
>
> Spring 的 `getBean(Class<T>)`、Jackson 的 `readValue(json, Class<T>)`、MyBatis 的很多 API，**全是同一招**。
>
> **看见方法签名里出现 `Class<T> xxx` 参数，几乎都是在绕擦除。** 从此这个参数不再是"多余的样板"，它有明确职责。

**代价（对照 C# 的 `new T()`）：**

- 调用方每次都得多写一个 `.class` —— **样板代码**
- 只能表达**光秃秃的类**：`List<String>.class` 是写不出来的。想传泛型类型只能上 `TypeReference<X>(){}` 那个匿名子类（`02` §7.2）
- 反射建实例有性能开销，且构造器不存在时运行期才炸

### 实验 2 · 看看 C# 少写了多少（只读，不用跑）

同一件事，三种写法并排：

```java
// Java：类型当参数传
static <T> T create(Class<T> type) { ... }
User u = create(User.class);
```

```csharp
// C#：类型就是类型
static T Create<T>() where T : new() => new T();
User u = Create<User>();
```

```kotlin
// Kotlin：inline + reified，编译期粘贴
inline fun <reified T> create(): T = T::class.java.newInstance()
val u = create<User>()
```

**Java 那行多出来的 `User.class`，就是擦除的税单。** 一次不多，一个项目里成百上千次。

### 实验 3 · 验证 Kotlin 的 reified 不是真 reified（思想实验）

不用装 Kotlin 也能推：

**问**：既然 Kotlin 能 `reified`，为什么它的**类**不能 reified？比如写不出 `class Box<reified T>`？

<details>
<summary>自己推完再展开</summary>

因为 `reified` 的实现是 **`inline` 展开**——把函数体粘贴到调用点，粘贴时类型已知，直接写死。

**而类没法 inline。** `Box<String>` 和 `Box<Int>` 得是运行期真实存在的两个不同的类，那就要求虚拟机支持生成两份——**回到了"必须改 JVM"这个死结**。

**结论**：Kotlin 的 `reified` 是**编译期把类型信息搬到调用点**，不是运行期真有类型。**它绕过了擦除，没有消灭擦除。**

—— 和 `02` §7.2 那个 `TypeReference<X>(){}` 的思路其实是同一类：**都是把类型信息从"实例"挪到一个"声明"上去。**
</details>

---

## 六、常见误解速查

| 误解 | 实际 |
|---|---|
| Java 泛型抄自 C++ | 同源于参数化多态，实现路线相反。直接前身是 GJ 不是 C++ |
| C++ 模板 = 泛型 | 更像带类型的宏展开。**不检查约束**，实例化才报错，C++20 的 concepts 才补上 |
| C# 泛型好说明 Java 设计烂 | C# 改了虚拟机，Java 不能。**约束不同，不是水平不同** |
| Kotlin 没有擦除 | 有。它跑在 JVM 上，限制一模一样，只是用 `inline+reified` 局部绕开 |
| `reified` 是运行期保留类型 | 是**编译期把函数体展开时写死类型**。所以只能用在 `inline` 函数上，类不行 |
| TS 的泛型和 Java 差不多 | TS 擦得更彻底——编译产物里连 `Signature` 都没有，运行期零痕迹 |
| 换语言就能摆脱擦除 | 只要还在 JVM 上就摆脱不了（Kotlin 那一列和 Java 几乎一样） |
| `Class<T>` 参数是多余的样板 | 它是**手工 reify** —— 把类型降级成普通值传进去，唯一能穿透擦除的常规办法 |
| Valhalla 快出了 | 2014 年开始，至今十余年未进正式版 |

---

## 七、回到本项目

### 7.1 你已经在付的三笔"擦除税"

| 位置 | 税 | 出处 |
|---|---|---|
| `JwtUtil.java:44-45` `claims.get("username", String.class)` | 多传一个 `Class<T>` | 实验 1 |
| `ProcessBackApplication.java:12` `run(ProcessBackApplication.class, args)` | 同上 | 实验 1 |
| `09` 文档 `toPage(query, ProcessInstanceVO::of, ...)` 必须传 mapper | 多传一个转换函数 | `05` §6.1 |

**第三笔最值得琢磨**：如果 Java 是 reified，`toPage` 里就能直接 `if (e is ProcessInstance)` 分派，`mapper` 参数根本不需要存在。

> **换句话说：`toPage` 那个让你卡了半天的签名，有一部分复杂度纯粹是擦除的产物。**
> 不是你笨，是这门语言在 1998 年替你做了一个决定。

### 7.2 前端那边同一件事

`process-front` 的 `PageResult<T>`、`api/instance.ts` 的返回类型标注——**编译完全部消失**，比 Java 擦得还干净。

所以后端 `R<T>` 传到前端，前端标 `R<ProcessInstanceVO>`，**两边的类型信息在运行期都不存在**。真正保证它们对得上的是：接口文档 + 你自己。**类型系统只在编译期帮你，跨进程它一点忙都帮不上。**

---

## 八、一句话总结

四条路的差别不在聪明程度，在**入场时的约束**：C++ 选编译期生成多份，换来零开销、付出代码膨胀和二十年报错地狱；C# 选运行期保留，换来几乎所有限制消失、付出"必须改虚拟机"这张 Java 出不起的门票；Kotlin 站在 JVM 上，**限制原封不动地继承下来**，只能用 `inline + reified` 局部绕；TS 擦得最彻底，运行期零痕迹。**Java 的所有别扭，追到底都是 1998 年那句 "Making the future safe for the past"。** 而实战里穿透擦除的常规办法只有一个：**把类型降级成普通参数传进去**（`Class<T>` token）——你项目的 `JwtUtil.java:44` 已经在用了。

---

## 九、往下可以再挖的

- **`08-回到toPage.md`**（**收官篇**）：合上全部文档重写一遍 `toPage`，外加 **什么时候不该写泛型**（`00` 里承诺的那条纪律，`06` §6.2 已经预演了一半）。写完就回主线做 Day 16 第 2–6 项。
- 未展开：**Project Valhalla 的 value class / 特化泛型**现状——想跟进就去看 JEP 401、JEP 402。
- 未展开：**Kotlin 的 `@JvmName`** 如何绕开擦除导致的重载撞车（`05` 后遗症 ④ 在 Kotlin 里的解法）。
- 未展开：**Spring 的 `ResolvableType` / `ParameterizedTypeReference`**——比 `TypeReference` 更完整的一套"在 Java 里操作泛型类型"的工具。哪天要写通用的 HTTP 客户端就会撞上。
