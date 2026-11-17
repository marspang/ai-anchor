#!/usr/bin/env bash
# claude-guard —— 出口 IP 与锚定 IP 不一致时阻止 Claude 继续使用
#
# 用法：
#   claude-guard.sh --check              只检测一次（0=正常 1=异常）
#   claude-guard.sh --watch              常驻守护（默认）
#   claude-guard.sh --watch --dry-run    只打印动作，不杀进程、不改 hosts
#   claude-guard.sh --install            安装为登录自启（macOS launchd）
#   claude-guard.sh --uninstall          卸载自启
#
# 配置：~/.config/claude-guard/config（可被 CLAUDE_GUARD_CONF 覆盖）

set -uo pipefail

CONF="${CLAUDE_GUARD_CONF:-$HOME/.config/claude-guard/config}"
EXPECT_IP=""
CHECK_URL="https://claude.ai/cdn-cgi/trace"
INTERVAL=15
THRESHOLD=2
APP_PATTERN="Claude.app/Contents/MacOS/Claude"
BLOCK_HOSTS=0
LOG="$HOME/.config/claude-guard/guard.log"

[ -f "$CONF" ] && . "$CONF"

MODE="watch"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --watch) MODE="watch" ;;
    --dry-run) DRY_RUN=1 ;;
    --install) MODE="install" ;;
    --uninstall) MODE="uninstall" ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$LOG")"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" >&2
}

notify() {
  local msg="$1"
  if [ "$(uname)" = "Darwin" ]; then
    osascript -e "display notification \"$msg\" with title \"claude-guard\"" >/dev/null 2>&1
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "claude-guard" "$msg" >/dev/null 2>&1
  fi
}

fetch_ip() {
  curl -s --max-time 8 "$CHECK_URL" 2>/dev/null | awk -F= '/^ip=/{print $2; exit}'
}

kill_claude() {
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] 将结束进程: $APP_PATTERN"
    return 0
  fi
  pkill -f "$APP_PATTERN" >/dev/null 2>&1 && log "已结束 Claude 进程"
}

HOSTS_MARK_BEGIN="# >>> claude-guard"
HOSTS_MARK_END="# <<< claude-guard"

block_hosts() {
  [ "$BLOCK_HOSTS" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] 将写入 hosts 阻断 claude.ai / api.anthropic.com"
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    log "跳过 hosts 阻断：需要免密 sudo，未配置"
    return 0
  fi
  if grep -q "$HOSTS_MARK_BEGIN" /etc/hosts 2>/dev/null; then
    return 0
  fi
  sudo tee -a /etc/hosts >/dev/null <<EOF
$HOSTS_MARK_BEGIN
127.0.0.1 claude.ai
127.0.0.1 api.anthropic.com
127.0.0.1 console.anthropic.com
$HOSTS_MARK_END
EOF
  log "已写入 hosts 阻断；注意：Clash fake-ip 生效时 hosts 不生效，仅在代理失效时起作用"
}

unblock_hosts() {
  [ "$BLOCK_HOSTS" = 1 ] || return 0
  [ "$DRY_RUN" = 1 ] && { log "[dry-run] 将移除 hosts 阻断"; return 0; }
  grep -q "$HOSTS_MARK_BEGIN" /etc/hosts 2>/dev/null || return 0
  sudo -n true 2>/dev/null || { log "跳过 hosts 恢复：需要免密 sudo"; return 0; }
  sudo awk -v b="$HOSTS_MARK_BEGIN" -v e="$HOSTS_MARK_END" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' /etc/hosts | sudo tee /etc/hosts.new >/dev/null && sudo mv /etc/hosts.new /etc/hosts
  log "已移除 hosts 阻断"
}

check_once() {
  local ip
  ip="$(fetch_ip)"
  if [ -z "$EXPECT_IP" ]; then
    log "[ERROR] 未配置 EXPECT_IP，请在 $CONF 中填写锚定的住宅 IP"
    return 2
  fi
  if [ "$ip" = "$EXPECT_IP" ]; then
    log "[OK] 出口正常：$ip"
    return 0
  fi
  log "[FAIL] 出口异常：当前=${ip:-取不到} 期望=$EXPECT_IP"
  return 1
}

watch() {
  local fails=0 blocked=0 ip
  log "开始守护：期望=$EXPECT_IP 间隔=${INTERVAL}s 阈值=$THRESHOLD dry-run=$DRY_RUN"
  while :; do
    ip="$(fetch_ip)"
    if [ -n "$EXPECT_IP" ] && [ "$ip" = "$EXPECT_IP" ]; then
      fails=0
      if [ "$blocked" = 1 ]; then
        unblock_hosts
        blocked=0
        log "[RECOVER] 出口恢复正常，已解除保护"
        notify "出口已恢复，可以继续使用 Claude"
      fi
    else
      fails=$((fails + 1))
      log "[FAIL $fails/$THRESHOLD] 当前=${ip:-取不到} 期望=$EXPECT_IP"
      if [ "$fails" -ge "$THRESHOLD" ]; then
        if [ "$blocked" = 0 ]; then
          kill_claude
          block_hosts
          notify "出口 IP 异常，已关闭 Claude。当前 ${ip:-无网络}"
          blocked=1
        else
          kill_claude
        fi
      fi
    fi
    sleep "$INTERVAL"
  done
}

install_launchd() {
  local plist="$HOME/Library/LaunchAgents/com.local.claude-guard.plist"
  local script
  script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.claude-guard</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$script</string><string>--watch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/.config/claude-guard/launchd.err.log</string>
  <key>StandardOutPath</key><string>$HOME/.config/claude-guard/launchd.out.log</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" >/dev/null 2>&1
  launchctl load "$plist" && echo "已安装并启动：$plist"
}

uninstall_launchd() {
  local plist="$HOME/Library/LaunchAgents/com.local.claude-guard.plist"
  launchctl unload "$plist" >/dev/null 2>&1
  rm -f "$plist"
  echo "已卸载"
}

case "$MODE" in
  check) check_once ;;
  watch) watch ;;
  install) install_launchd ;;
  uninstall) uninstall_launchd ;;
esac
