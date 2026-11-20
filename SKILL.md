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

## 先判定部署模式：主路由还是旁路由

这一步决定后面“哪些设备走代理”怎么配，配错方向整个方案就是空的。先跑三条命令：

```bash
ip -4 route | grep default           # 默认网关指向谁
uci get network.lan.gateway          # 自己有没有上游网关
uci get dhcp.lan.ignore              # 本机 DHCP 是否关闭（1=关）
```

| 判定 | 主路由 | 旁路由 |
| --- | --- | --- |
| 默认网关 | 指向 `pppoe-wan` 或 wan 口 | 指向另一台内网设备（如 `192.168.31.1`） |
| `network.lan.gateway` | 为空 | 有值，且不等于本机 |
| 谁在拨号 | 本机 | 上游设备 |

### 两种模式的分流逻辑完全不同

| | 主路由（家里的用法） | 旁路由（公司的用法） |
| --- | --- | --- |
| 默认行为 | **所有设备都走代理** | **所有设备都不走代理** |
| 例外怎么加 | 白名单设备在规则里写 `SRC-IP-CIDR,192.168.1.23/32,DIRECT` | 想让谁走代理，就把谁的网关 / DNS 指到这台旁路由 |
| 例外写在哪 | OpenClash 的规则里 | 上游 DHCP 或设备本身的网络设置里，**不在 OpenClash 里** |
| 规则末尾 | `MATCH → 🤖 AI住宅IP` 兜底 | 同样兜底，但只对“已经把网关指过来”的设备生效 |
| 故障影响 | 全家断网 | 只有把网关指过来的设备断网 |

一句话：**主路由是“默认全走，逐个放行直连”；旁路由是“默认都不走，逐个接进来”。** 旁路由上再写设备白名单是没有意义的——没把网关指过来的设备，它的流量根本不经过这台机器，规则一条都不会命中。

### 旁路由的两种接法

同样是旁路由，接入方式不同，结果也不同。先选一种，别混用。

| | DHCP 接管（公司常见） | 手动指向（设备少时用） |
| --- | --- | --- |
| 谁能用上代理 | 所有自动获取 IP 的设备 | 只有手动改过网络设置的设备 |
| 怎么配 | 上游关 DHCP；旁路由开 DHCP，下发 `192.168.31.88` 作为网关和 DNS | 保留上游 DHCP；逐台把网关 + DNS 改成旁路由 IP |
| 影响范围 | 全网；旁路由挂了全员断网 | 只影响改过的那几台 |
| 主要风险 | 与上游双 DHCP 冲突、故障半径大 | 设备续租或换网卡后会悄悄变回直连，必须定期复查 |
| 适合 | 设备多、希望统一管控 | 只有一两台要代理，不想打扰别人 |

两种接法都要在客户端实测一次：

```bash
# 网关是不是旁路由
netstat -rn | grep '^default'        # macOS
route print 0.0.0.0                  # Windows
```

### 旁路由必须确认的六件事

1. **DHCP 只能有一个。** 旁路由接管 DHCP（上游关 DHCP），或上游只把 `option 3/6` 指向旁路由，两种选一种。两边同时开就是双 DHCP，客户端网关随机飘，表现为“有时走代理有时不走”。
2. **没指过来的设备完全不受控。** 它的 AI 流量直接从上游出去，你的规则、DNS、IPv6 关闭全部无效。所以旁路由模式下“谁在用 Claude”这件事必须逐个确认。
3. **IPv6 关不掉全局。** 在旁路由上关 IPv6 只影响它自己；客户端仍会从上游路由器的 RA 拿到全局 IPv6，双栈直连出去，绕过整个代理。要真关掉，必须在上游路由器关 IPv6/RA，或在客户端侧禁用 IPv6。
4. **TUN / fake-ip 只对“以本机为网关”的流量生效**；旁路由自己出网走上游，别在这台机器上再开一个代理客户端，否则就是双入口。
5. **上游如果有自己的代理或 VPN，先确认它没接管 AI 域名**，否则流量在到达旁路由之前就被转走了。
6. **交付时要写清楚故障半径**：旁路由挂了，哪些设备会断网。公司环境这一点必须提前告知使用者。

### 只允许一台设备登录 Claude

同一个网络里只要有第二台设备用同一个账号，出口 IP 再干净也会被判“多设备共用”。做法是**按源 IP 白名单**：只放行指定设备，其余设备访问 AI 域名直接 `REJECT`，从网络层断掉连坐的可能。

前提：给放行的那台设备做 **DHCP 静态租约**，IP 固定下来（例如 `192.168.31.229`），否则重连后租约变了规则就失效。

规则放在 AI 域名规则之前：

```
AND,((SRC-IP-CIDR,192.168.31.229/32),(RULE-SET,ai)),🤖 AI住宅IP
RULE-SET,ai,REJECT
```

如果内核版本不支持逻辑规则（`clash -t` 会直接报错），退回两段式，代价是这台设备的非国内流量也走住宅 IP：

```
SRC-IP-CIDR,192.168.31.229/32,🤖 AI住宅IP
RULE-SET,ai,REJECT
```

验证必须两头都做：

```bash
# 放行设备：应当正常
curl -s -o /dev/null -w '%{http_code}\n' https://claude.ai/login
# 其他设备：应当超时或连接被拒
curl -s --max-time 8 -o /dev/null -w '%{http_code}\n' https://claude.ai/login
```

注意三点：

- `REJECT` 是 fail-closed，同事装 Claude 也会被挡，交付时必须提前告知，别让人以为断网了。
- 这条只管“走旁路由的流量”；手动指向模式里没改网关的设备不经过规则，管不到。
- 手机 / 平板在同一个 WiFi 下同样会被这条规则挡住，这正是想要的效果。

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
  - 旁路由额外一步：本机 `ipv6: false` 只关掉自己。客户端仍可能从上游 RA 拿到全局 IPv6 直连，用 `curl -6 https://claude.ai/cdn-cgi/trace` 在客户端实测；能返回地址就说明 IPv6 仍在绕过代理，必须到上游关 RA，或在客户端禁用 IPv6
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
- 订阅自带的 AI 组如果已被规则引用，**就地改它的 `type` 与成员，保持组名不变**；改名要同步规则和 DNS，纯风险无收益
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
2. 国内 AI 域名 → `DIRECT`（清单见下；必须在 AI 域名规则**之前**，否则会被兜底规则带去住宅 IP）
3. AI 域名 → `🤖 AI住宅IP`（清单见下，必须全量）
4. Adobe 域名 → `DIRECT`
5. Microsoft Office/365 域名 → `DIRECT`
6. `GEOSITE,cn` / `GEOIP,CN` → `DIRECT`
7. `MATCH → 🤖 AI住宅IP`（兜底走住宅 IP，等效“全局”但保留国内直连；漏配的子域、冷门 CDN、桌面客户端都不会直连暴露真实 IP）

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

**为什么单独列一份国内 AI 直连清单：** 这些域名如果漏掉，会被末尾的 `MATCH` 兜底送去住宅 IP。结果是国内 AI 变慢、每次都绕一圈美国，而且平白给住宅 IP 增加一堆和本人使用习惯无关的访问特征。放在 AI 域名规则**之前**，确保它们永远走直连。

## 国内 AI 直连清单（放在 AI 域名规则之前）

```
deepseek.com, api.deepseek.com, chat.deepseek.com,
moonshot.cn, kimi.com, kimi.moonshot.cn,
tongyi.aliyun.com, dashscope.aliyuncs.com, bailian.console.aliyun.com,
doubao.com, volcengine.com, ark.cn-beijing.volces.com,
yiyan.baidu.com, wenxin.baidu.com, qianfan.baidubce.com,
chatglm.cn, bigmodel.cn, open.bigmodel.cn, zhipuai.cn,
hunyuan.tencent.com, minimax.cn, minimaxi.com, stepfun.com
```

不在清单里的国内 AI 服务，按同样规则补一行即可；判断方法很简单——**服务主体在国内、账号在国内注册、付费走国内渠道，就走直连。**

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
6. 时区/语言与住宅 IP 归属地一致（设备端单独设置，关掉自动设置）。
7. 指纹稳定：不频繁换 UA、不频繁清指纹、不同时开多个浏览器配置。
8. 指纹一致：字体、屏幕分辨率、时区、语言跟着出口地区走；出差回来别让系统自己改回去。
9. 设备与账号：同一台设备不登录多个账号，同一账号不在多设备多 IP 同时在线——平台按「设备指纹 + 账号」做关联，换号不换设备等于换名不换人。
10. 账号面信息：绑定手机号、支付方式、邮箱地区与出口地区一致。
11. 会话期间不切节点：`store-selected` 生效，重启后仍是同一节点。
12. 规则命中校验：`clash -t` + OpenClash 日志确认 AI 请求命中 `🤖 AI住宅IP`。
13. 所有改动文件先备份 `.bak.<日期>`。
14. 整链路体检：用 `https://ip.net.coffee/claude/` 实测。
15. 浏览器层：用 noleaker（时区/语言跟随出口，拦 WebRTC、DNS、QUIC 泄漏）。
16. 系统层：出口守护，出口 ≠ 锚定 IP 时杀 Claude 进程 + 阻断，见 `references/guard-design.md`。

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
   - 是否独享：服务商有没有明确写 dedicated；共享住宅池里前手的使用记录会算在你头上
   - 历史信誉：`scamalytics` / `ipqualityscore` 免费查询，fraud score 越低越好，出现「高风险 / 滥用」直接换 IP
   - rDNS / ASN：反查应指向住宅 ISP，而不是伪装成住宅段的机房
   任一不达标先定位（DNS / UDP / 规则未命中），修完复测，不要直接交差。
4. 规则命中：看 OpenClash 运行日志，确认走的是 `🤖 AI住宅IP` / `DIRECT`。
5. 持久化：重启 OpenClash（不是整机），重跑 1–3，结果不变。
6. 最后输出表格：项目 / 做法 / 校验结果 / 回滚命令。

## 配置完成后必须核对（验收清单）

上一节是「跑什么命令」，这一节是「怎么判定它真的成了」。逐项过，任何一项不过都不算交付。

| # | 检查项 | 通过标准 |
| --- | --- | --- |
| 1 | 改动落在哪一层 | 组 / 规则 / DNS 全在 `/etc/openclash/custom/`；点一次「更新配置」后重新核对仍然生效。改订阅源 `config/<name>.yaml` 的一律不算通过 |
| 2 | 出口归属 | 报告里必须有 `country / isp / as / proxy / hosting` 五个字段；地区在 Claude 支持范围内，`proxy` 与 `hosting` 均为 `false` |
| 3 | 三方一致 | `ipinfo.io/ip` = `claude.ai/cdn-cgi/trace` = `chatgpt.com/cdn-cgi/trace`，三个字符串完全相同 |
| 4 | 兜底规则 | 规则最后一条是 `MATCH → AI 住宅组`；兜底是 DIRECT 或被删等于把漏网流量打回真实 IP |
| 5 | 规则总量 | 至少 70 条（AI 33 + Adobe 11 + Office 12 + 内网 12 + geosite 2 + UDP 1 + MATCH 1）；明显偏少说明清单被截断 |
| 6 | Adobe / Office 全量 | Adobe 11 条（含 `adobelogin` / `creativecloud` / `acrobat` / `licensing`）、Office 12 条（含 `microsoftonline` / `msftconnecttest` / `windowsupdate` / `microsoftstore`） |
| 7 | AI 域名 DNS | 每条 AI 域名显式指定远端 DoH，不依赖 `geosite:geolocation-!cn` 归类（geosite 版本不同、子域未必收录） |
| 8 | 端口收敛 | 只剩面板 9090、DNS 7874、TUN；`http / socks / redir / tproxy / mixed` 全为 0 |
| 9 | QUIC 拦截持久化 | 规则写在 `/etc/nftables.d/` 或 `uci firewall`；重启后 `nft list ruleset` 里仍在。临时 `nft add` 不算 |
| 10 | 回滚可用 | 备份文件路径与恢复命令里的路径一致；关掉几个端口就恢复几个；改配置**前**先空跑一遍 `cp` 确认源文件存在 |
| 11 | IP 静默变化有感知 | `select` 单节点不会换 IP，但服务商换 IP 也不会断流；装了出口守护且 `EXPECT_IP` = 锚定 IP，`--check` 返回 0 |
| 12 | 体检截图 | `ip.net.coffee/claude` 的实测截图，不接受「应该仍是全绿」 |
| 13 | IP 是否干净 | 独享住宅段（非共享池）；scamalytics / ipqualityscore 无高风险或滥用标记；rDNS 指向住宅 ISP |
| 14 | 本机体检 | 在用户机器上跑 `scripts/claude-risk-audit.sh`，FAIL 项清零，或逐条说明为什么不影响 |

### 交付报告的红线

- 禁止用「应该」「理论上」「大概率」描述验证结果；跑过就贴完整输出，没跑就明写没跑
- 「原状态」与「现在」两列要对得上，数量自洽（说 6 处就列 6 行，⚠ 也算一处）
- 备份路径、恢复路径、文件权限三者在报告里必须一致，回滚命令要先自己验证一次文件存在
- `clash -t` 只接受退出码 `0`，不接受「只剩下 -t 模式对 UI 路径的误报」这种说法
- 说「QUIC 绕不过去」必须附 UDP 出口实测：`udp: true` 只是允许，不代表服务端真的转发

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
- 家和公司两处用：不要一边一个出口，优先让笔记本回连家里（Tailscale exit node），两处共用同一个住宅 IP。细节见 `references/claude-usage.md` 第十节。

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
- Windows 用 `scripts/claude-guard.ps1`，支持 `-Check / -Watch / -DryRun / -Install / -Uninstall`，**不支持 hosts 阻断**（`BLOCK_HOSTS` 忽略），杀进程只覆盖桌面客户端，浏览器里的 claude.ai 管不到
  - 已在 Windows 11 24H2 + PowerShell 5.1 实机跑通；`.ps1` 必须保存为 **UTF-8 with BOM**，否则中文系统上 5.1 按 GBK 解析中文注释会直接语法报错
  - 通过 SSH 远程测杀进程时，GUI 程序（如 notepad）在非交互会话里起不来，用 `ping -t 127.0.0.1` 之类常驻进程代替，`APP_NAME` 改成对应名字

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
