<h1 align="center">ai-anchor</h1>

<h3 align="center">给 AI 流量打一个钉子：把出口 IP 固定成同一个静态住宅地址<br>国内与 Adobe / Office 照常直连，Claude 只认这一个出口</h3>

<p align="center">
<a href="https://github.com/marspang/ai-anchor"><img src="https://img.shields.io/badge/%E7%89%88%E6%9C%AC-v1.0.0-f1c40f?style=for-the-badge" alt="版本"></a>
<a href="https://github.com/marspang/ai-anchor"><img src="https://img.shields.io/badge/%E5%BD%A2%E5%BC%8F-Agent%20Skill-2f81f7?style=for-the-badge" alt="形式"></a>
<img src="https://img.shields.io/badge/%E5%86%85%E6%A0%B8-OpenClash%20%C2%B7%20mihomo-fe7d37?style=for-the-badge" alt="内核">
<img src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-macOS%20%C2%B7%20Linux%20%C2%B7%20Windows-3fb950?style=for-the-badge" alt="平台">
<img src="https://img.shields.io/badge/%E7%9B%AE%E6%A0%87-%E9%99%8D%E4%BD%8E%E5%B0%81%E5%8F%B7-e35d6a?style=for-the-badge" alt="目标">
</p>

`ai-anchor` 是一个给 **AI Agent 用的技能包**（Skill），不是脚本合集。丢给 TRAE / Qoder / Qwen Code / WorkBuddy / Claude Code 这类能执行命令的 Agent，它会自己登路由器、认固件、看现有配置、改 OpenClash，再把 AI 出口钉死在一个静态住宅 IP 上。

它不管你怎么把流量送出去——那是订阅和节点的事；它只解决**「怎么让 Claude 看到的世界永远不变」**。

## 目录

- [它到底在钉什么](#它到底在钉什么) · [支持的设备与实测情况](#支持的设备与实测情况)
- [快速开始](#快速开始) · [两种线路怎么接](#两种线路怎么接)
- [三层防封组合](#三层防封组合)
- [出口守护脚本](#出口守护脚本)
- [给最终用户的使用说明](#给最终用户的使用说明)
- [目录结构](#目录结构)
- [常见问题 FAQ](#常见问题-faq)
- [致谢与许可](#致谢与许可)

AI 服务商的风控里有一条几乎是硬判据：

> - [x] 看出口 IP 的归属地和属性（住宅 / 机房）
> - [ ] 保证同一个账号始终从同一个出口出现

第一项各家都在做，第二项**没人替你做**——订阅是机场给的，节点池是轮询的，掉线重连就换了一台机器。

**这个仓库就是来补第二项的**：

1. **单出口** —— AI 域名全部命中 `🤖 AI住宅IP` 组，这个组里**只有一个节点**，`select` 固定，禁止 fallback / url-test / 负载均衡。切节点就是换 IP，换 IP 就是封号高发点；
2. **准全局兜底** —— 规则末尾放 `MATCH → 🤖 AI住宅IP`。等效“全局”，但国内、Adobe、Office 仍然直连，不会为了防封把正常办公一起废掉；
3. **出口守护** —— 机器一旦离开这个网络（换 WiFi、连手机热点、代理掉线），出口 IP 变了就立刻杀掉 Claude 进程 + 阻断域名，恢复后自动解除。人忘了，程序不会忘。

---

## 它到底在钉什么

一句话：**Claude 只认出口 IP，不认你在哪。**

你在家、在公司、在高铁上都不重要；你的请求从哪个 IP 出去才重要。所以整套配置只围绕三件事：

| 要防的 | 怎么做 |
| --- | --- |
| IP 漂移 | AI 组只放一个静态住宅节点，`store-selected: true`，重启后还是它 |
| 域名漏走 | AI 域名清单全量入规则，再补 `MATCH` 兜底，冷门子域也无处可逃 |
| 旁路泄漏 | `ipv6: false` + TUN 接管 TCP/UDP + AI 域名强制远端 DoH 解析，防 DNS / QUIC 裸奔 |

配置完的判定标准也很直白，三条命令必须是同一个 IP：

```bash
curl -s --max-time 10 https://ipinfo.io/json
curl -s --max-time 10 https://claude.ai/cdn-cgi/trace | grep ip=
curl -s --max-time 10 https://chatgpt.com/cdn-cgi/trace | grep ip=
```

---

## 支持的设备与实测情况

先说清楚这是给哪类设备用的：**下面这些 OpenWrt / ImmortalWrt / iStoreOS / LibWrt 都是路由器固件**，装在一台单独的机器上（AX6、N1、x86 小主机、工控机这类，统称**软路由**），由它统一给全家设备分流。它不是装在 Windows / macOS 里的软件，装在自己电脑上不管用。

没有软路由也不是完全用不上：**mihomo 内核的桌面客户端**（Clash Verge Rev、mihomo party 等）规则、代理组、DNS、TUN 这套完全通用，可以照搬，只是技能不会去操作客户端 GUI，需要自己改配置；**iPhone / iPad 上的 Shadowrocket** 能导入 Clash 配置，代理组和规则大体能套，但手机换一次网络就换一次出口，只适合临时应急；**v2rayN / V2Ray 系**规则模型不同，配置不能直接套，只能借用「单出口 + 兜底 + 防泄漏」的思路。

| 平台 | 部署路线 | 相关文件 | 实测状态 |
| --- | --- | --- | --- |
| **软路由**（OpenWrt / ImmortalWrt / iStoreOS / LibWrt） | OpenClash + mihomo，`custom/` 覆盖注入 | `SKILL.md` | ✅ **公司路由器实机改过配置**（custom 注入、`clash -t` 预校验、规则命中均验证）；住宅线路待换 |
| **Windows / macOS + Clash Verge Rev（mihomo 内核）** | 手工改配置：单成员代理组、规则顺序、DNS 照搬 | —— | ⚪ 配置模型通用，未逐版本实测 |
| **iPhone / iPad + Shadowrocket** | 导入 Clash 配置，代理组与规则大体通用 | —— | ❌ 配置能套，但手机换网即换出口，不建议用同一账号在手机上登录 |
| **macOS** | launchd 常驻出口守护 | `scripts/claude-guard.sh` | ✅ **本机完整闭环验证**（正常 → 异常触发 → 持续拦截 → 恢复 RECOVER） |
| **Linux（Debian / Ubuntu）** | systemd user / NetworkManager dispatcher | `scripts/claude-guard.sh` | ⚪ 同构方案，脚本逻辑与 macOS 共线，未逐台跑 |
| **Windows 10 / 11** | `schtasks` 登录自启 + PowerShell | `scripts/claude-guard.ps1` | ⚪ 已写好，**无机器可跑**，未实测 |
| **手机 / 平板（其他客户端）** | —— | `references/claude-usage.md` | ❌ 不提供方案，**建议不要在手机上登录同一账号** |

- **必须是 mihomo 内核**：原版 Clash 不支持 vless，`clash -t` 会直接报错。要求 mihomo ≥ v1.19（Reality 需要 ≥1.18）。
- **纯 REDIRECT 模式不在覆盖范围**：本技能只走 `TUN + fake-ip`，全机单一入口。TUN 和系统代理同时开会造成双入口，本身就是风控特征。
- **路由器白名单不是默认项**：一个人住、只有一台设备用 Claude 的网络，加白名单纯属给自己找麻烦。只有「这个网有别人连、别人也用 Claude」时才需要，见 FAQ。

---

## 快速开始

### 方式一：装成 Agent 技能（推荐）

把 `ai-anchor/` 整个目录放进对应 Agent 的技能目录：

```bash
git clone https://github.com/marspang/ai-anchor.git /tmp/ai-anchor

# TRAE / 通用全局技能目录
cp -R /tmp/ai-anchor ~/.trae-cn/skills/ai-anchor
```

之后直接说「帮我把 AI 出口固定到这个住宅 IP」，Agent 会命中这个技能并开始执行。`SKILL.md` 是纯 Markdown + YAML frontmatter，没有脚本依赖，任何读得懂 skill 的 Agent 都能用。

### 方式二：只把提示词丢给 Agent

不想装技能也行。把 `SKILL.md` 正文整段复制给 Agent，效果一样——它本来就是一份可以独立执行的操作手册，只是少了自动触发的入口。

### 方式三：自己照着做

`SKILL.md` 的执行流程是 A→F 六段，按顺序读下去就是一份手工配置指南：

| 段落 | 做什么 |
| --- | --- |
| A | 先采集：读现有 YAML、确认 fake-ip + TUN、核对 `custom/` 四个文件、看内核版本 |
| B | 运行参数：订阅转换、`store-selected`、关 IPv6、开 custom 规则、UDP 接管 |
| C | 代理组：建 `🤖 AI住宅IP`（单节点）与 `🔒 直连白名单`，注入后 `clash -t` 预校验 |
| D | 规则：局域网直连 → AI 域名 → Adobe → Office → `GEOSITE,cn` → `MATCH` 兜底 |
| E | DNS：fake-ip-filter、nameserver-policy、`proxy-server-nameserver` |
| F | 内网生效：DHCP 下发路由器自身 DNS，重启 dnsmasq，终端重连 |

> 所有改动都落在 `/etc/openclash/custom/` 下，**不碰订阅本身**，订阅更新也不会覆盖。每个文件改前先备份 `.bak.<日期>`。

---

## 两种线路怎么接

技能只需要你给**一行**线路信息，剩下的自己识别，不让用户再拆一次。

| 你手上的东西 | 长什么样 | 技能怎么处理 |
| --- | --- | --- |
| 订阅链接 | `https://...` | 填订阅 → 开订阅转换 → 在转换结果里挑出住宅节点 → 注入代理组 |
| 账号密码串 | `203.0.113.10:8001:username:password` | 解析成 server / port / user / pass，探协议，写成 `type: socks5` 或 `type: http` 节点 |

账号密码型线路会先跑两条探测，**哪种通就用哪种**：

```bash
curl -s --max-time 10 --noproxy '*' -x "http://USER:PASS@HOST:PORT"    https://ipinfo.io/json
curl -s --max-time 10 --noproxy '*' -x "socks5h://USER:PASS@HOST:PORT" https://ipinfo.io/json
```

- socks5 通 → `type: socks5` + `udp: true`，能接管 QUIC，才算零泄漏；
- 只有 http 通 → `type: http`，并**必须**补一条 `AND,((NETWORK,UDP),(DST-PORT,443)),REJECT`，否则 QUIC 直连绕过代理，TUN 开着也白开。

配之前还有一道拦截，命中任一条就停下告诉你，不硬配：

```bash
curl -s "http://ip-api.com/json/出口IP?fields=country,city,isp,as,proxy,hosting"
```

- 地区属于 Claude 不支持范围（中国大陆、香港、俄罗斯、伊朗等）；
- `hosting=true` 或 `proxy=true`（机房 / 代理标记，不是真住宅）。

> 这两条不是洁癖。拿一个香港机房 IP 去配 Claude，配得再完美也只是**把封号流程标准化**。

---

## 三层防封组合

单靠路由器只覆盖了一层，完整方案是三层叠起来，缺一层就有缺口：

| 层 | 做什么 | 归属 | 状态 |
| --- | --- | --- | --- |
| **网络层** | 单出口、单入口、无 DNS/IPv6/QUIC 泄漏 | 路由器（本仓库 `SKILL.md`） | ✅ 可自动化 |
| **浏览器层** | 时区 / 语言跟随出口 IP，拦 WebRTC、DNS、QUIC 泄漏 | 浏览器扩展（如 noleaker） | ⚪ 需手动装 |
| **系统层** | 出口 ≠ 锚定 IP 时杀进程 + 阻断域名 | 本仓库 `scripts/` | ✅ 已实测（macOS） |

配套的 13 条防封清单在 `SKILL.md` 里逐条打勾，包含「会话期间不切节点」「同账号不多设备多 IP 同时在线」「支付 / 邮箱地区与 IP 一致」这类非技术项——**很多封号不是配置问题，是行为问题**。

---

## 出口守护脚本

`scripts/claude-guard.sh`（macOS / Linux）与 `scripts/claude-guard.ps1`（Windows）解决的是同一个场景：

> 你带着笔记本出门，连上了咖啡店的 WiFi，代理没起来，Claude 自己连上去了。

脚本每 `INTERVAL` 秒请求一次 `https://claude.ai/cdn-cgi/trace` 取 `ip=`，连续 `THRESHOLD` 次对不上锚定 IP 就判定出口异常，立刻 `kill` 掉 Claude 进程并可选写 hosts 阻断；恢复后打一条 `[RECOVER]` 自动解除。

### 配置

配置文件固定在 `~/.config/claude-guard/config`，`KEY=VALUE`，被 `source` 读取：

```bash
EXPECT_IP=203.0.113.10          # 你锚定的那个住宅 IP
CHECK_URL=https://claude.ai/cdn-cgi/trace
INTERVAL=15                     # 轮询间隔（秒）
THRESHOLD=2                     # 连续失败几次判定异常
APP_PATTERN="Claude.app/Contents/MacOS/Claude"
BLOCK_HOSTS=0                   # 1 = 同时写 hosts 阻断（需要免密 sudo）
```

### 用法

| 参数 | 作用 |
| --- | --- |
| `--check` | 只查一次，出口正确返回 `0`，错误返回 `1`（适合塞进别的脚本） |
| `--watch` | 常驻轮询，异常即杀进程 |
| `--watch --dry-run` | 只打日志不杀进程，**先跑这个确认不会误杀** |
| `--install` | 写 `~/Library/LaunchAgents/com.local.claude-guard.plist` 并加载（Linux 用 systemd user unit） |
| `--uninstall` | 卸载自启并停止 |

推荐顺序，一步都别跳：

```bash
./claude-guard.sh --check                  # 当前出口对不对
./claude-guard.sh --watch --dry-run        # 观察几分钟，看有没有误报
./claude-guard.sh --install                # 确认没问题再常驻
```

### 验证方法

不用等出事，改个配置就能测：

```bash
EXPECT_IP=1.2.3.4 ./claude-guard.sh --check   # 应该返回 1
EXPECT_IP=<真实IP> ./claude-guard.sh --check  # 应该返回 0
```

### 已知局限

- **hosts 阻断需要免密 sudo**（`sudo -n`），否则自动降级为「只杀进程」，不报错；
- **误杀风险**：`APP_PATTERN` 是字符串匹配，改过安装路径要同步改配置；
- **不是防火墙**：它管的是 Claude 这个应用，不是整机出口。真正的断网保护在网络层；
- **Windows 版未实机验证**，首次使用请先 `-Check` 与 `-Watch -DryRun` 跑一轮。

---

## 给最终用户的使用说明

`references/claude-usage.md` 是给**真正用 Claude 的那个人**看的，不是给运维看的。九条，核心就这几句：

- **Claude 只认出口 IP，不认你在哪**。换网络不致命，出口变了才致命。
- **台式机**：能接网线就接网线；有无线网卡的外台式机关掉无线，避免开机自动连手机热点。**只能靠 WiFi 的台式机不要关网卡**，改成把陌生热点设为手动连接。
- **笔记本**：外出先跑出口校验，没代理就不要开 Claude。
- **手机**：**最保险的做法是完全不用手机登录同一个账号**。移动网络出口天天变，一次就够。
- **开机顺序**：先代理，后浏览器。
- **时区 / 语言**：关掉「自动设置」，出差回来别让系统自己改。
- **出事第一件事**：查出口 IP 是不是还是锚定的那个。

```bash
curl -s --max-time 8 https://claude.ai/cdn-cgi/trace | grep ip=
```

网络隔离的具体命令（忘掉陌生 WiFi、关无线网卡、笔记本外出处理）在 `references/network-isolation.md`，分 macOS / Windows / Linux 三段，都带回滚。

---

## 目录结构

```
ai-anchor/
├── SKILL.md                       技能主文件：适用场景 / 输入 / A-F 执行流程 / 域名清单 / 13 条防封清单 / 交付要求
├── references/
│   ├── claude-usage.md            给最终用户的 9 条使用说明
│   ├── network-isolation.md       三平台网络隔离命令（忘 WiFi / 关网卡 / 外出处理）
│   └── guard-design.md            出口守护设计：三层组合、配置示例、部署、误杀防护、路由器白名单
└── scripts/
    ├── claude-guard.sh            macOS / Linux 出口守护（launchd / systemd）
    └── claude-guard.ps1           Windows 出口守护（schtasks）
```

---

## 常见问题 FAQ

**Q：我家只有一台设备用 Claude，还要做路由器白名单吗？**

**A：** 不用。白名单是给「这个网有别人连、别人也用 Claude」的场景准备的，加了只是给自己增加维护成本。

**Q：那什么情况下要做？**

**A：** 办公室、合租、家里有别人也订阅了 Claude。做法是**只隔离 Claude**：静态 DHCP 把用 Claude 的设备绑成固定 IP，白名单设备走 `🤖 AI住宅IP`，其余设备的 `claude.ai` / `anthropic.com` 走 `REJECT`。Gemini、GPT、Office 一律不动——别为了防一个封号把全屋网络搞瘫。

**Q：我已经开了「全局模式」，是不是更安全？**

**A：** 不是。全局会连带国内服务和 Adobe / Office 一起绕出去，体验变差还多绕一跳；真正的收益和「准全局」一样。用 `MATCH` 兜底等效全局，但保留了直连。

还有一类更实际的原因：有些本地软件会拿出口 IP 判断授权状态，一旦发现请求来自境外地址，就可能要求重新验证授权、或者干脆拒绝启动。这类软件留在直连清单里，能省掉一堆莫名其妙的麻烦——所以「直连」不是顺手做的事，是刻意留的口子。

**Q：为什么不能用 fallback / url-test 组？**

**A：** 因为它们的本质是「自动换节点」，也就是自动换 IP。对 Claude 来说，这比断线更糟。

**Q：节点是香港的机房 IP，能用吗？**

**A：** 不能。Claude 不支持香港地区，且 `hosting=true` 是明确的机房标记。技能会在配置前拦截并让你去找服务商换美国 / 日本真住宅段。

**Q：配完 `claude.ai` 打得开，但 `ip.net.coffee/claude` 体检不通过？**

**A：** 按顺序查：DNS 是否泄漏（AI 域名有没有走远端 DoH）→ UDP / QUIC 是否漏（节点支不支持 UDP 转发，`http` 型线路有没有加 `REJECT` 规则）→ 规则是否真的命中（看 OpenClash 运行日志里走的是不是 `🤖 AI住宅IP`）。三项里通常至少中一项。

**Q：改了配置结果全屋断网？**

**A：** 说明没做 `clash -t` 预校验就重启了 OpenClash。这是本技能反复强调的硬性要求，改完先校验、失败自动回滚。已经断了的，从 `custom/` 的 `.bak` 恢复原配置再重启。

**Q：脚本会不会误杀我正在用的 Claude？**

**A：** `--watch --dry-run` 就是为这个准备的。先观察一轮日志，确认判定逻辑和你的网络行为一致，再 `--install`。

---

## 致谢与许可

- 思路参考了几个同方向的开源项目：**[cso1z/claude-ip-guard](https://github.com/cso1z/claude-ip-guard)**（Claude Code Hook 层做 IP 校验，MIT）、**[v2macapp/noleaker](https://github.com/v2macapp/noleaker)**（浏览器层拦 WebRTC / DNS / QUIC 并跟随出口时区语言，GPL-3.0）、**[vpn-kill-switch/killswitch](https://github.com/vpn-kill-switch/killswitch)**（macOS `pf` 断线保护）。本仓库的差异在**路由器侧单出口 + 准全局规则**这一层，三者组合起来才闭环。
- 整链路体检用的是 **[ip.net.coffee/claude](https://ip.net.coffee/claude/)**，能一次看到出口 IP、DNS 泄漏、UDP 泄漏和风险评分，比自己拼命令省事。
- 本仓库的 `SKILL.md`、参考文档与守护脚本供自用与技术交流。Claude / ChatGPT / Gemini 的服务条款由各家自行解释，**因使用本方案产生的账号风险由使用者自行承担**。
