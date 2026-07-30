#!/usr/bin/env bash
#
# check-links.sh —— 文档死链检查器
#
# 用途：把文档里每个「看起来像文档路径」的字符串拿到磁盘上实际查一遍，
#       而不是靠正则自查。文档搬家 / 改目录结构后必跑。
#
# 用法：
#   bash tools/check-links.sh              # 检查整个仓库
#   bash tools/check-links.sh --verbose    # 连忽略掉的也列出来（排查误判用）
#   bash tools/check-links.sh plan         # 只检查某个子目录
#
# 退出码：0 = 全部可达；1 = 发现死链（可用于 git hook / CI）
#
# 检查两种写法：
#   ① 反引号里的文件路径      `../05-重写排期计划.md`
#   ② markdown 链接           [文字](./plan/P4-业务前端批量.md)
# 路径一律按「相对于该文档所在目录」解析，锚点（#xxx）会被剥掉再查。

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

VERBOSE=0
SCOPE="."
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)            SCOPE="$arg" ;;
  esac
done

# ───────────────────────────────────────────────────────────────
# 忽略清单：这些不是「本仓库内的文档路径」，查不到属正常
# 判断在这里，改这里就能调整口径
# ───────────────────────────────────────────────────────────────
should_ignore() {
  case "$1" in
    # 外部链接
    http*|https*|mailto*)                       return 0 ;;
    # 项目源码路径（在代码仓库里，不在本仓库）
    src/*|sql/*|resources/*|processes/*|classpath:*) return 0 ;;
    node_modules/*|*/node_modules/*)            return 0 ;;
    views/*|api/*|router/*|layout/*|stores/*|utils/*|components/*) return 0 ;;
    index.html|*swagger*|*doc.html)             return 0 ;;
    # 本机配置，不随仓库走
    .claude*|CLAUDE.md|*/.claude/*)             return 0 ;;
    # 含空格 / 通配符的，多半是正文里的示意而非真路径
    *" "*|*"*"*)                                return 0 ;;
    # 空串
    "")                                         return 0 ;;
  esac
  return 1
}

# 尚未编写、但计划中要写的文件——引用它们是对的，不算死链
# 写完一篇就从这里删掉一行
is_planned() {
  case "$1" in
    */02-操作步骤.md|02-操作步骤.md)     return 0 ;;  # Day16 待写
    */03-完整代码.md|03-完整代码.md)     return 0 ;;  # Day16 待写
    */04-疑问与解答.md|04-疑问与解答.md) return 0 ;;  # Day16 待写
    */05-外围四表.md|05-外围四表.md)     return 0 ;;  # hi_tables 支线待写
  esac
  return 1
}

# ───────────────────────────────────────────────────────────────
dead=0; checked=0; ignored=0; planned=0

while IFS= read -r f; do
  d=$(dirname "$f")
  {
    # ① 反引号里的 .md / .html
    grep -oE '`[^`]*\.(md|html)`' "$f" 2>/dev/null | tr -d '`'
    # ② markdown 链接 [xx](yy)
    #    只认「像路径的」——含 / 或以 .md/.html 结尾。
    #    否则会把代码里的 generator["throw"](value) 这类误当成链接。
    grep -oE '\]\([^)]*\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//' \
      | grep -E '(/|\.md$|\.html$|\.md#|\.html#)'
  } | sed 's/#.*//' | while IFS= read -r p; do
    if should_ignore "$p"; then
      [ "$VERBOSE" = 1 ] && echo "  · 忽略  ${f#./}  →  $p"
      continue
    fi
    if [ -e "$d/$p" ]; then
      echo "OK"
    elif is_planned "$p"; then
      [ "$VERBOSE" = 1 ] && echo "  ○ 待写  ${f#./}  →  $p"
      echo "PLANNED"
    else
      echo "DEAD ${f#./} → $p"
    fi
  done
done < <(find "$SCOPE" -name "*.md" -not -path "./.git/*" -not -path "*/.git/*") > /tmp/_links.$$ 2>/dev/null

checked=$(grep -c . /tmp/_links.$$ 2>/dev/null || echo 0)
planned=$(grep -c '^PLANNED' /tmp/_links.$$ 2>/dev/null || echo 0)
mapfile -t deads < <(grep '^DEAD ' /tmp/_links.$$ 2>/dev/null | sed 's/^DEAD //' | sort -u)
rm -f /tmp/_links.$$

echo "════════════════════════════════════════════"
echo " 文档死链检查  ($ROOT)"
echo "════════════════════════════════════════════"
if [ "${#deads[@]}" -eq 0 ]; then
  echo " ✅ 全部可达"
  echo "    检查引用 $checked 处（其中计划中待写 $planned 处）"
  exit 0
else
  echo " ❌ 发现 ${#deads[@]} 条死链："
  printf '    %s\n' "${deads[@]}"
  echo ""
  echo " 提示：若属误判，把模式加进脚本的 should_ignore() 或 is_planned()"
  exit 1
fi
