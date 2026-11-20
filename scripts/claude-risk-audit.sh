#!/usr/bin/env bash
# claude-risk-audit —— 本机封号风险体检（只读，不改任何东西）
#
# 用法：
#   ./claude-risk-audit.sh            输出中文报告
#   ./claude-risk-audit.sh --quiet    只输出 FAIL / WARN
#
# 检查 6 项：出口 IP 属性、时区语言一致性、账号痕迹、会话频率、Shell 批量痕迹、本机代理残留。
# 退出码：0 = 无 FAIL；1 = 至少一项 FAIL；2 = 缺少依赖无法完成

set -uo pipefail

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

FAILS=0
WARNS=0

ok()   { [ "$QUIET" = 1 ] || printf '[OK]    %s\n' "$*"; }
warn() { WARNS=$((WARNS+1)); printf '[WARN]  %s\n' "$*"; }
fail() { FAILS=$((FAILS+1)); printf '[FAIL]  %s\n' "$*"; }
skip() { [ "$QUIET" = 1 ] || printf '[SKIP]  %s\n' "$*"; }
head_() { [ "$QUIET" = 1 ] || printf '\n== %s ==\n' "$*"; }

jsonval() {
  printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" | head -1
}

# ---------- 1. 出口 IP ----------
head_ "1. 出口 IP 属性"

IPJSON="$(curl -s --max-time 8 'http://ip-api.com/json/?fields=status,country,countryCode,city,isp,as,proxy,hosting,query' 2>/dev/null)"
SRC="ip-api.com"
if [ -z "$IPJSON" ] || ! printf '%s' "$IPJSON" | grep -q '"status":"success"'; then
  IPJSON="$(curl -s --max-time 8 'https://ipinfo.io/json' 2>/dev/null)"
  SRC="ipinfo.io"
fi

if [ -z "$IPJSON" ]; then
  fail "取不到出口 IP（ip-api / ipinfo 都无响应），先确认代理是否正常"
  IP=""; COUNTRY=""; CC=""
elif [ "$SRC" = "ipinfo.io" ]; then
  IP="$(jsonval "$IPJSON" ip)"
  CC="$(jsonval "$IPJSON" country)"
  COUNTRY="$CC"
  ISP="$(jsonval "$IPJSON" org)"
  ASN="$ISP"
  PROXY="unknown"; HOSTING="unknown"
  printf '        出口=%s 地区=%s ISP=%s（来源 %s，未含 proxy/hosting 字段）\n' "${IP:-?}" "${CC:-?}" "${ISP:-?}" "$SRC"
  case "$CC" in
    CN|HK|RU|IR|KP) fail "出口地区 $CC 不在 Claude 支持范围" ;;
    "") skip "地区字段为空" ;;
    *) ok "出口地区 $CC" ;;
  esac
  skip "当前数据源不含 hosting/proxy，用 ip.net.coffee 或 ipqualityscore 补查"
else
  IP="$(jsonval "$IPJSON" query)"
  COUNTRY="$(jsonval "$IPJSON" country)"
  CC="$(jsonval "$IPJSON" countryCode)"
  ISP="$(jsonval "$IPJSON" isp)"
  ASN="$(jsonval "$IPJSON" as)"
  PROXY="$(jsonval "$IPJSON" proxy)"
  HOSTING="$(jsonval "$IPJSON" hosting)"
  printf '        出口=%s 地区=%s(%s) ISP=%s ASN=%s\n' "${IP:-?}" "${COUNTRY:-?}" "${CC:-?}" "${ISP:-?}" "${ASN:-?}"
  case "$CC" in
    CN|HK|RU|IR|KP) fail "出口地区 $CC 不在 Claude 支持范围" ;;
    "") skip "地区字段为空" ;;
    *) ok "出口地区 $CC" ;;
  esac
  [ "$HOSTING" = "true" ] && fail "hosting=true：机房 IP，不是住宅" || ok "hosting=false"
  [ "$PROXY" = "true" ] && fail "proxy=true：被标记为代理出口" || ok "proxy=false"
fi

# ---------- 2. 时区 / 语言 ----------
head_ "2. 时区 / 语言一致性"

TZNAME="$(readlink /etc/localtime 2>/dev/null | sed 's|.*zoneinfo/||')"
[ -z "$TZNAME" ] && TZNAME="$(date +%Z)"
LOCALE="$(defaults read -g AppleLocale 2>/dev/null || echo "${LANG:-}")"
LANGS="$(defaults read -g AppleLanguages 2>/dev/null | tr -d '\n ' | head -c 60)"

printf '        时区=%s 区域=%s 语言=%s\n' "${TZNAME:-?}" "${LOCALE:-?}" "${LANGS:-?}"

case "$CC" in
  US) case "$TZNAME" in America/*) ok "时区与出口地区一致" ;; *) fail "出口是美国但时区=${TZNAME}，平台会判定为异地操作" ;; esac ;;
  JP) case "$TZNAME" in Asia/Tokyo) ok "时区与出口地区一致" ;; *) warn "出口日本，时区=${TZNAME}" ;; esac ;;
  CN) case "$TZNAME" in Asia/Shanghai|Asia/Chongqing) ok "时区与出口地区一致" ;; *) warn "出口中国，时区=${TZNAME}" ;; esac ;;
  "") skip "无出口地区，跳过时区比对" ;;
  *) [ -n "$TZNAME" ] && warn "时区=${TZNAME}，出口=${CC}，人工确认是否一致" ;;
esac

# ---------- 3. 账号痕迹 ----------
head_ "3. 账号痕迹"

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  warn "环境里存在 ANTHROPIC_API_KEY，与 OAuth 登录共存容易被判定为多入口"
else
  ok "未发现 ANTHROPIC_API_KEY 环境变量"
fi

if [ -f "$HOME/.claude/.credentials.json" ]; then
  MODE=$(stat -f '%Lp' "$HOME/.claude/.credentials.json" 2>/dev/null || stat -c '%a' "$HOME/.claude/.credentials.json" 2>/dev/null)
  if [ -n "$MODE" ] && [ "$MODE" != "600" ]; then
    warn "~/.claude/.credentials.json 权限是 ${MODE}，建议 chmod 600"
  else
    ok "OAuth 凭据存在且权限正常"
  fi
else
  skip "未找到 ~/.claude/.credentials.json"
fi

if [ -f "$HOME/.claude.json" ] && grep -q 'oauthAccount' "$HOME/.claude.json" 2>/dev/null; then
  ok "存在 OAuth 账号记录"
fi

# ---------- 4. 会话频率 ----------
head_ "4. 会话频率（近 7 天）"

if ! command -v python3 >/dev/null 2>&1; then
  skip "没有 python3，跳过频率分析"
elif [ ! -d "$HOME/.claude/projects" ]; then
  skip "未找到 ~/.claude/projects"
else
  python3 - "$HOME/.claude/projects" <<'PY'
import json, os, sys, time, collections
root = sys.argv[1]
cutoff = time.time() - 7*86400
stamps = []
files = 0
for dirpath, _, names in os.walk(root):
    for n in names:
        if not n.endswith('.jsonl'):
            continue
        p = os.path.join(dirpath, n)
        try:
            if os.path.getmtime(p) < cutoff:
                continue
            files += 1
            with open(p, encoding='utf-8', errors='ignore') as f:
                for line in f:
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    ts = o.get('timestamp')
                    if not ts:
                        continue
                    try:
                        t = time.mktime(time.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S'))
                    except Exception:
                        continue
                    stamps.append(int(t))
        except Exception:
            continue
stamps.sort()
if not stamps:
    print('[OK]    近 7 天没有可分析的会话记录')
    sys.exit(0)
per_sec = collections.Counter(stamps)
per_min = collections.Counter(s // 60 for s in stamps)
max_sec = max(per_sec.values())
max_min = max(per_min.values())
days = len({s // 86400 for s in stamps})
print(f'        文件={files} 消息={len(stamps)} 活跃天数={days} 峰值={max_sec}/秒 {max_min}/分')
if max_sec > 5:
    print(f'[FAIL]  峰值 {max_sec} 条/秒，属于脚本化调用特征')
elif max_min > 60:
    print(f'[FAIL]  峰值 {max_min} 条/分钟，属于脚本化调用特征')
elif max_min > 20:
    print(f'[WARN]  峰值 {max_min} 条/分钟，接近脚本化阈值')
else:
    print('[OK]    频率在对话式使用范围内')
PY
fi

# ---------- 5. Shell 批量痕迹 ----------
head_ "5. Shell 批量痕迹"

HISTFILES=""
for f in "$HOME/.zsh_history" "$HOME/.bash_history"; do
  [ -f "$f" ] && HISTFILES="$HISTFILES $f"
done

if [ -z "$HISTFILES" ]; then
  skip "没有可读的 shell history"
else
  COUNT=0
  for f in $HISTFILES; do
    C=$(grep -acE '(for|while) .*claude|xargs[^|]*claude|sub2api' "$f" 2>/dev/null || true)
    COUNT=$((COUNT + ${C:-0}))
  done
  if [ "$COUNT" -gt 0 ]; then
    warn "history 中有 $COUNT 条批量调用 Claude 的痕迹（for/xargs/sub2api）"
  else
    ok "未发现批量调用痕迹"
  fi
fi

# ---------- 6. 本机代理残留 ----------
head_ "6. 本机代理残留"

if [ "$(uname)" = "Darwin" ]; then
  PROXYCONF="$(scutil --proxy 2>/dev/null)"
  if printf '%s' "$PROXYCONF" | grep -qE 'HTTPEnable *: *1|HTTPSEnable *: *1|SOCKSEnable *: *1'; then
    warn "系统代理已开启，和路由器 TUN 同时存在就是双入口"
  else
    ok "系统代理未开启"
  fi
  LISTEN="$(lsof -nP -iTCP:7890 -iTCP:7891 -iTCP:7893 -sTCP:LISTEN 2>/dev/null | tail -n +2)"
else
  LISTEN="$(ss -lntp 2>/dev/null | grep -E ':(7890|7891|7893)\b')"
  [ -n "$LISTEN" ] && warn "本机有代理端口在监听：$LISTEN" || ok "本机无常见代理端口监听"
fi
[ -n "${LISTEN:-}" ] && [ "$(uname)" = "Darwin" ] && warn "本机有代理端口在监听，确认是否与路由器入口冲突"

# ---------- 汇总 ----------
head_ "汇总"
printf '        FAIL=%d WARN=%d\n' "$FAILS" "$WARNS"
if [ "$FAILS" -gt 0 ]; then
  echo "        先处理 FAIL 项：出口属性 / 时区 / 会话频率是权重最高的三项。"
  exit 1
fi
[ "$WARNS" -gt 0 ] && echo "        没有硬伤，WARN 项按提示逐条收紧即可。"
exit 0
