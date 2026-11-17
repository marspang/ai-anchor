---
name: ai-anchor
description: AI 锚定（ai-anchor）——在 OpenWrt（ImmortalWrt / iStoreOS / LibWrt 等）+ OpenClash 路由器上，把 AI 流量固定到一个静态住宅 IP、国内与 Adobe/Office 直连的完整配置技能。覆盖订阅节点与「服务器:端口:账号:密码」两种线路接入、TUN/fake-ip、规则注入、DNS 防泄漏、Claude 防封清单，以及用 ip.net.coffee/claude 做整链路体检。当用户提到 OpenClash、住宅 IP、AI 走代理、AI 锚定、Claude 防封、给路由器配代理、AI 分流时使用。
---

# OpenClash 静态住宅 IP · AI 分流配置

## 适用场景

用户要把路由器上所有 AI 工具的出口固定成一个静态住宅 IP，同时国内流量和 Adobe / Office 走直连，并尽量降低 Claude / ChatGPT / Gemini 风控概率。

运行环境需要具备 shell / SSH 能力（TRAE、Qoder、Qwen Code、WorkBuddy 等可执行命令的 Agent）。纯聊天客户端不支持本技能，不要接单。

## 输入

只需要一项线路信息，二选一，自己识别，不要让用户再拆一次：

1. 订阅链接：`https://...`
2. 账号密码串，一行：`服务器:端口:账号:密码`
   例：`203.0.113.10:8001:username:password`
   这属于 HTTP / SOCKS5 账号密码型代理，走「账号密码型线路」分支，不要当订阅填。

其余信息（LAN IP、SSH 账号、固件型号、OpenClash 版本、内核版本）自己登上去查，查不到再问。

## 目标

1. AI 出口 100% 固定为同一个住宅 IP，会话期间绝不切换。
2. 国内流量、Adobe 全家桶、Office / 365 直连。
3. 其余未命中流量兜底走住宅 IP（等效“全局”，但不牺牲国内与办公软件直连）。
4. 最大化降低 Claude / ChatGPT / Gemini 封号概率。
5. 交付：改动文件清单、每步校验结果、回滚方法。

## 执行流程

### A. 先采集，不要直接改
- `cat /etc/openclash/config/*.yaml`，看现有 proxy-groups / rules 结构
- 确认运行模式：必须 `fake-ip + TUN`，关闭 REDIRECT 与系统代理，全机只留 TUN 一个入口
- 确认 `/etc/openclash/custom/` 下 4 个文件是否存在：
  `openclash_custom_rules.list`、`openclash_custom_rules_2.list`、`openclash_custom_overwrite.sh`、`openclash_custom_domain_dns_policy.list`
- 记录内核版本：`/etc/openclash/core/clash_meta -v`，要求 mihomo ≥ v1.19
- OpenClash 本身是否 enabled、订阅是否为空、custom 目录是否还是模板——这三项是“配了不生效”的常见原因，先排除

### B. 运行参数
- 填入订阅并「更新配置」，开启订阅转换（convert）
- `store-selected: true`（重启后保持已选节点）
- `ipv6: false`（防 IPv6 绕过代理裸奔）
- `enable_custom_clash_rules=1`
- 节点协议优先 vless / vmess 且服务端支持 UDP 转发；不要用 SS / Trojan / Hysteria 顶替（部分实现不转发 UDP，QUIC 会直连暴露真实 IP）
- 打开 TUN 接管 TCP + UDP；「全局模式」开关保持关闭，用兜底规则实现等效全局
- TUN stack 选 gvisor 或 system，开 DNS 劫持；TUN 与系统代理不同时启用
- 订阅里若有多种协议的同类住宅节点，先列出来让用户确认，不要猜

### C. 代理组（写进 openclash_custom_overwrite.sh，订阅更新不覆盖）
- 新建 `🤖 AI住宅IP`，`type: select`，唯一成员 = 静态住宅节点
  - 禁止 fallback / url-test / load-balance / relay
  - 禁止放多个节点（切换 IP 是封号高发点）
- 新建 `🔒 直连白名单`，`type: select`，成员仅 DIRECT
- 注入后立刻 `clash -t -f 生成的配置` 预校验，失败自动回滚

### C-2. 账号密码型线路（HOST:PORT:USER:PASS）
1. 自己解析 server / port / username / password。
2. 探测协议，两条都跑：
   ```
   curl -s --max-time 10 --noproxy '*' -x "http://USER:PASS@HOST:PORT" https://ipinfo.io/json
   curl -s --max-time 10 --noproxy '*' -x "socks5h://USER:PASS@HOST:PORT" https://ipinfo.io/json
   ```
3. 选型：
   - socks5 通 → `type: socks5` + `udp: true`（能接管 QUIC，才谈得上零泄漏）
   - 只有 http 通 → `type: http`，并必须补一条丢 UDP/443 的规则强制回落 TCP：
     `AND,((NETWORK,UDP),(DST-PORT,443)),REJECT`
     否则 QUIC 绕过代理直连，真实 IP 暴露，TUN 开着也没用
4. 注入模板（放 proxies 数组最前面）：
   ```yaml
   {name: "🏠 住宅IP", type: socks5, server: HOST, port: PORT,
    username: USER, password: PASS, udp: true}
   ```
   http 版把 type 换成 http、删掉 udp 字段。
5. 节点名固定 `🏠 住宅IP`，`🤖 AI住宅IP` 组只放它一个。
6. 没有订阅，不需要订阅转换；配完确认在线：
   `curl -s http://127.0.0.1:9090/proxies | grep -A3 '住宅IP'`（看 alive 是否 true）
7. 配之前先查出口归属，命中任一条就停下告诉用户，不要继续配：
   - 国家/地区属于 Claude 不支持地区（中国大陆、香港、俄罗斯、伊朗等）
   - `hosting=true` 或 `proxy=true`（机房/代理标记，不是真住宅）
   ```
   curl -s "http://ip-api.com/json/出口IP?fields=country,city,isp,as,proxy,hosting"
   ```

### D. 规则（写进 openclash_custom_rules.list，置顶，顺序不能乱）
1. 局域网/保留地址 → `DIRECT,no-resolve`
2. AI 域名 → `🤖 AI住宅IP`（清单见下，必须全量）
3. Adobe 域名 → `DIRECT`
4. Microsoft Office/365 域名 → `DIRECT`
5. `GEOSITE,cn` / `GEOIP,CN` → `DIRECT`
6. `MATCH → 🤖 AI住宅IP`（兜底走住宅 IP，等效“全局”但保留国内直连；漏配的子域、冷门 CDN、桌面客户端都不会直连暴露真实 IP）

### E. DNS
- fake-ip 模式，`fake-ip-filter` 放行局域网与 `*.lan`
- nameserver-policy：
  - `geosite:cn` → `223.5.5.5, 119.29.29.29`
  - `geosite:geolocation-!cn` → `https://1.1.1.1/dns-query`
  - AI 域名 → `https://1.1.1.1/dns-query`（强制代理解析，防 DNS 泄露）
- 关闭“绕过中国大陆 IP”引起的劫持冲突
- `proxy-server-nameserver` 单独配置，用于解析节点域名（否则节点解析失败会整组掉线）

### F. 内网设备生效
- DHCP 下发 DNS 必须指向路由器自身，不能下发 223.5.5.5，否则终端解析真实 IP 直连，规则形同虚设
- 改完重启 dnsmasq，终端断开重连一次

## AI 域名清单（全量）

anthropic.com, claude.ai, claudeusercontent.com, claude.com, statsig.anthropic.com, api.anthropic.com, console.anthropic.com,
openai.com, chatgpt.com, oaistatic.com, oaiusercontent.com, sora.com,
gemini.google.com, bard.google.com, aistudio.google.com, makersuite.google.com, generativelanguage.googleapis.com, ai.google.dev, deepmind.google, proactivebackend-pa.googleapis.com, alkalimakersuite-pa.clients6.google.com, accounts.google.com, notebooklm.google.com,
x.ai, grok.com, perplexity.ai, poe.com, copilot.microsoft.com, midjourney.com, huggingface.co, cursor.com, cursor.sh, moonshot.ai

（deepseek.com 在国内使用时给 DIRECT。）

## Adobe 直连清单

adobe.com, adobelogin.com, adobe.io, adobecc.com, adobeccs.com, cctype.com, assets.adobe.com, photoshop.com, creativecloud.adobe.com, acrobat.adobe.com, licensing.adobe.com

## Office / Microsoft 直连清单

office.com, office365.com, microsoft.com, microsoftonline.com, live.com, outlook.com, sharepoint.com, onedrive.com, msftconnecttest.com, windowsupdate.com, microsoftstore.com

## 防封清单（逐条打勾）

1. 单出口：AI 组只有一个住宅节点，select 固定，禁止自动切换。
2. 单入口：TUN 与系统代理不同时开。
3. 无 IPv6 泄漏。
4. 无 DNS 泄漏：AI 域名经代理或远端 DoH 解析，IP 规则加 `no-resolve`。
5. 无 QUIC 旁路：节点必须 vless/vmess 且支持 UDP，TUN 接管 UDP。
6. 时区/语言与住宅 IP 归属地一致（设备端单独设置）。
7. 指纹稳定：不频繁换 UA、不频繁清指纹；同账号不多设备多 IP 同时在线。
8. 会话期间不切节点：`store-selected` 生效，重启后仍是同一节点。
9. 规则命中校验：`clash -t` + OpenClash 日志确认 AI 请求命中 `🤖 AI住宅IP`。
10. 所有改动文件先备份 `.bak.<日期>`。
11. 整链路体检：用 `https://ip.net.coffee/claude/` 实测。
12. 浏览器层：用 noleaker（时区/语言跟随出口，拦 WebRTC、DNS、QUIC 泄漏）。
13. 系统层：出口守护，出口 ≠ 锚定 IP 时杀 Claude 进程 + 阻断，见 `references/guard-design.md`。

## 自测（必须真跑，贴输出）

1. 出口一致性：
   ```
   curl -s --max-time 10 https://ipinfo.io/json
   curl -s --max-time 10 https://claude.ai/cdn-cgi/trace | grep ip=
   curl -s --max-time 10 https://chatgpt.com/cdn-cgi/trace | grep ip=
   ```
   两者必须是同一 IP。账号密码型线路还要贴：协议探测结果、出口 IP、国家/城市、proxy / hosting 标记。
2. 可用性：`claude.ai`、`gemini.google.com`、`adobe.com`、`office.com` 各返回 200，记录耗时。
3. IP 风险体检（浏览器打开并截图）`https://ip.net.coffee/claude/`：
   - Trust Score ≥ 70（< 50 不合格）
   - IP 属性为「住宅 / ISP / 原生」，不是「机房 / 数据中心」
   - VPN / 代理 / Tor / 机器人 / 滥用记录 均为「无」
   - DNS 未泄露，DNS 出口 IP 与 Claude 出口 IP 同地区
   - WebRTC / UDP 未泄露，UDP 出口 IP 与出口 IP 一致
   - 时区、语言与 IP 归属地一致
   - 中国出口 IPv4、Cloudflare 出口 IP、Claude 出口 IP 三者一致
   任一不达标先定位（DNS / UDP / 规则未命中），修完复测，不要直接交差。
4. 规则命中：看 OpenClash 运行日志，确认走的是 `🤖 AI住宅IP` / `DIRECT`。
5. 持久化：重启 OpenClash（不是整机），重跑 1–3，结果不变。
6. 最后输出表格：项目 / 做法 / 校验结果 / 回滚命令。

## 交付

### 1. 给用户的使用说明（必须给，不能省略）

读 `references/claude-usage.md`，整理成中文交给用户。核心观点必须保留：

- **Claude 只认出口 IP，不认你在哪**。换网络不致命，出口变了才致命。
- 台式机：有线优先；有无线网卡就关掉，避免开机自动连手机热点。
- 笔记本：外出先跑出口校验，没代理就不要开 Claude，也不要用手机 App 登同一账号。
- 手机：不要用移动网络直接登录同一账号。
- 开机顺序：先代理、后浏览器。
- 时区 / 语言关闭「自动设置」，避免出差后与 IP 不一致。
- 出事第一件事：查出口 IP 是否还是锚定的那个。

### 2. 网络隔离加固（问用户是否执行）

读 `references/network-isolation.md`，按平台给命令。至少做两件事：

- 生成「出口守卫」脚本（需要用户提供锚定 IP），并当场验证：关代理必须报异常，开代理必须通过。
- 能接网线的台式机关闭无线网卡；只能靠 Wi-Fi 的台式机不要关，改为把陌生热点设为手动连接。
- 笔记本把陌生 WiFi 改为手动连接。

约束：不要擅自删除用户的 WiFi 配置，先列出来让用户勾选；不要关掉用户正在使用的那张网卡。

### 3. 出口守护（可选，推荐）

读 `references/guard-design.md`。用户同意后：

- 复制 `scripts/claude-guard.sh` 到本机，配置 `~/.config/claude-guard/config`，`EXPECT_IP` 用当前锚定 IP
- 顺序：`--check` → `--watch --dry-run` → `--install`
- 必须现场验证两次：把 `EXPECT_IP` 改错时返回 1，改回时返回 0
- Windows 用 `scripts/claude-guard.ps1`，参数相同

### 4. 路由器白名单（可选，先问，不要默认做）

先问一句：「这个网络会不会有别人连，而且也用 Claude？」

- 不会（一个人住、只有一台设备用 Claude）→ 跳过，不要加任何限制
- 会 → 只隔离 Claude，Gemini / GPT / Office 一律不动
  做法见 `references/guard-design.md` 第八节：静态 DHCP 绑定 MAC → 固定 IP，白名单设备走 `🤖 AI住宅IP`，其余设备的 `claude.ai` / `anthropic.com` 走 `REJECT`

## 禁止事项

- 不用 fallback / url-test 承载 AI 流量
- 不把域名硬编码进 proxy-groups 的 proxies 列表（订阅更新会失效）
- 未做 `clash -t` 预校验不重启 OpenClash（会全内网断网）
- 不改订阅本身 YAML，全部走 `custom/` 覆盖
- 找不到住宅节点时停下来问，不拿普通节点顶替
