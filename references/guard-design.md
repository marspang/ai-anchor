# Claude 出口守护：设计与部署

## 一、为什么不是「关掉 Claude」

关闭只是表面动作：用户随时能重开，重开的那几秒已经用真实 IP 发了请求。
所以守护程序做两件事，缺一不可：

1. **阻断**：出口异常时让 claude.ai 无法访问（hosts 或防火墙），而不是只关窗口。
2. **关闭**：结束正在运行的 Claude 进程，让当前会话立即中断。

恢复出口后自动撤销阻断，不需要用户手动改回来。

## 二、判据：出口 IP，不是「连了哪个 WiFi」

每 15 秒请求一次 `https://claude.ai/cdn-cgi/trace`，取 `ip=` 字段与锚定的住宅 IP 比对。
这个请求走的是应用层，代理生效时它返回住宅 IP，代理失效时返回宽带/热点 IP，
能覆盖「换网络」「代理崩溃」「TUN 掉线」三种情况。

取不到 IP（连接超时）同样算异常 —— 这是最重要的一个分支，它能在代理刚挂掉时立刻触发。

## 三、三层组合（不要重复造轮子）

| 层 | 用什么 | 负责什么 |
| --- | --- | --- |
| 路由器 | OpenClash 规则 | 让 AI 域名只走住宅 IP，兜底也走住宅 |
| 浏览器 | [noleaker](https://github.com/v2macapp/noleaker) | 时区/语言/地理跟随出口，拦 WebRTC、DNS、QUIC 泄漏 |
| 命令行 | [claude-ip-guard](https://github.com/cso1z/claude-ip-guard) | Claude Code 每次请求前查 IP，受限地区直接拦 |
| 系统 | 本目录 `claude-guard` | 出口不对时杀进程 + 阻断 + 通知 |

noleaker 在 TUN 模式下没有 kill switch（只有 SOCKS5 模式有），所以系统层的守护不能省。

## 四、部署

### 配置

统一放在 `~/.config/claude-guard/config`（Windows 是 `%USERPROFILE%\.config\claude-guard\config`）：

```ini
EXPECT_IP=203.0.113.10
CHECK_URL=https://claude.ai/cdn-cgi/trace
INTERVAL=15
THRESHOLD=2
APP_PATTERN=Claude.app/Contents/MacOS/Claude
BLOCK_HOSTS=0
```

Windows 用同一份文件，键名一致，多一个 `APP_NAME=Claude`。

`BLOCK_HOSTS=1` 需要免密 sudo（macOS/Linux），没配置会自动降级为「只杀进程 + 通知」。

### macOS / Linux

```bash
chmod +x scripts/claude-guard.sh
./scripts/claude-guard.sh --check        # 先单次验证
./scripts/claude-guard.sh --watch --dry-run   # 观察一轮，确认判据正确
./scripts/claude-guard.sh --install      # 登录自启
```

`--install` 写 `~/Library/LaunchAgents/com.local.claude-guard.plist`，`KeepAlive` 常驻。
Linux 用 systemd：

```ini
# ~/.config/systemd/user/claude-guard.service
[Unit]
Description=claude-guard
[Service]
ExecStart=/bin/bash %h/.config/claude-guard/claude-guard.sh --watch
Restart=always
[Install]
WantedBy=default.target
```

```bash
systemctl --user enable --now claude-guard
```

### Windows（管理员 PowerShell）

```powershell
.\scripts\claude-guard.ps1 -Check
.\scripts\claude-guard.ps1 -Watch -DryRun
.\scripts\claude-guard.ps1 -Install
```

`-Install` 注册计划任务 `claude-guard`，登录时以最高权限启动。

## 五、误杀防护

| 风险 | 处理 |
| --- | --- |
| 代理重启导致短暂不一致 | 连续 2 次失败才触发（阈值可调） |
| 网络抖动 | 取不到 IP 也计数，但恢复后立即清零并解除阻断 |
| 用户正在保存文档 | 只杀 Claude 进程，不碰浏览器和其他应用 |
| hosts 残留 | 恢复时按标记段整段删除，不会破坏已有 hosts 内容 |

## 六、验证方法（无住宅线路时也能做）

1. `--check` 用一个故意写错的 `EXPECT_IP` 跑，必须返回 1 并打印当前 IP。
2. 改回真实出口 IP，必须返回 0。
3. `--watch --dry-run` 观察：断网或关代理后，应在 2 个周期内打印「将结束进程」，恢复后打印 RECOVER。
4. 真机验证杀进程：把 `APP_PATTERN` 临时改成 `Safari`，确认能杀掉，再改回来。

## 七、已知局限

- **浏览器标签无法优雅关闭**：强杀浏览器会丢所有标签，所以浏览器层靠 hosts 阻断或 noleaker，不靠杀进程。
- **Clash fake-ip 会让 hosts 失效**：所以 hosts 只在代理已经失效时起作用，正好是需要的场景；代理正常时不需要阻断。
- **桌面客户端可能自动重连**：阻断期间脚本每个周期都会再杀一次，直到出口恢复。
- **时钟漂移**：设备时间不准会导致 TLS 失败，脚本会误判为「取不到 IP」。开启系统自动对时。

## 八、路由器侧：只隔离 Claude（可选）

只有当这个网络**有可能被别人连上**时才需要，一个人住且只有一台设备用 Claude 的情况可以跳过。

思路：静态 DHCP 绑定 MAC → 固定 IP，然后只对非白名单设备拒绝 Claude 域名，Gemini/GPT 照常放行。

```
# 白名单设备正常走 AI 组；其他设备的 Claude 域名直接拒绝
AND,((SRC-IP-CIDR,192.168.100.50/32),(DOMAIN-SUFFIX,claude.ai)),🤖 AI住宅IP
AND,((SRC-IP-CIDR,192.168.100.50/32),(DOMAIN-SUFFIX,anthropic.com)),🤖 AI住宅IP
DOMAIN-SUFFIX,claude.ai,REJECT
DOMAIN-SUFFIX,anthropic.com,REJECT
```

规则要放在 AI 域名规则之前。不要给 Gemini、OpenAI、Office 加同样的限制。
