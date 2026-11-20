<h1 align="center">ai-anchor</h1>

<h3 align="center">给 AI 流量打一个钉子：把出口 IP 固定成同一个静态住宅地址<br>国内与 Adobe / Office 照常直连，Claude 只认这一个出口</h3>

<p align="center">
<a href="https://github.com/marspang/ai-anchor"><img src="https://img.shields.io/badge/%E7%89%88%E6%9C%AC-v1.2.0-f1c40f?style=for-the-badge" alt="版本"></a>
<a href="https://github.com/marspang/ai-anchor"><img src="https://img.shields.io/badge/%E5%BD%A2%E5%BC%8F-Agent%20Skill-2f81f7?style=for-the-badge" alt="形式"></a>
<img src="https://img.shields.io/badge/%E5%86%85%E6%A0%B8-OpenClash%20%C2%B7%20mihomo-fe7d37?style=for-the-badge" alt="内核">
<img src="https://img.shields.io/badge/%E7%9B%AE%E6%A0%87-%E9%98%B2%E6%AD%A2%E5%9B%A0%E7%BD%91%E7%BB%9C%E9%97%AE%E9%A2%98%E5%AF%BC%E8%87%B4%E7%9A%84%E5%B0%81%E5%8F%B7-e35d6a?style=for-the-badge" alt="目标">
</p>

`ai-anchor` 是一个给 **AI Agent 用的技能包**（Skill），不是脚本合集。丢给 TRAE / Qoder / Qwen Code / WorkBuddy / Claude Code 这类能执行命令的 Agent，它会自己登路由器、认固件、看现有配置、改 OpenClash，再把 AI 出口钉死在一个静态住宅 IP 上。

它不管你怎么把流量送出去——那是订阅和节点的事；它只解决**「怎么让 Claude 看到的世界永远不变」**。

## 目录

- [它到底在钉什么](#它到底在钉什么) · [支持的设备与实测情况](#支持的设备与实测情况)
- [快速开始](#快速开始) · [两种线路怎么接](#两种线路怎么接)
- [三层防封组合](#三层防封组合) · [它治不了什么](#它治不了什么)
- [出口守护脚本](#出口守护脚本)
- [给最终用户的使用说明](#给最终用户的使用说明)
- [人不在家怎么办](#人不在家怎么办多地点)
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

![ai-anchor 拓扑：设备经软路由分流，AI 固定到静态住宅 IP，国内与办公软件直连](docs/topology.svg)

配置完的判定标准也很直白，三条命令必须是同一个 IP：

```bash
curl -s --max-time 10 https://ipinfo.io/json
curl -s --max-time 10 https://claude.ai/cdn-cgi/trace | grep ip=
curl -s --max-time 10 https://chatgpt.com/cdn-cgi/trace | grep ip=
```

---

## 支持的设备与实测情况

先说清楚这是给哪类设备用的：**下面这些 OpenWrt / ImmortalWrt / iStoreOS / LibWrt 都是路由器固件**，装在一台单独的机器上（AX6、N1、x86 小主机、工控机这类，统称**软路由**），由它统一给全家设备分流。它不是装在 Windows / macOS 里的软件，装在自己电脑上不管用。

没有软路由也不是完全用不上：**mihomo 内核的桌面客户端**（Clash Verge Rev、mihomo party 等）规则、代理组、DNS、TUN 这套完全通用，可以照搬，只是技能不会去操作客户端 GUI，需要自己改配置；**Shadowrocket**（Apple 芯片的 Mac 上也能装）同样能导入 Clash 配置，代理组和规则大体能套，在 Mac 上可以当桌面客户端用；**v2rayN / V2Ray 系**规则模型不同，配置不能直接套，只能借用「单出口 + 兜底 + 防泄漏」的思路。手机 / 平板一律不建议，理由见表格最后一行。

| 平台 | 部署路线 | 相关文件 | 实测状态 |
| --- | --- | --- | --- |
| **软路由**（OpenWrt / ImmortalWrt / iStoreOS / LibWrt） | OpenClash + mihomo，`custom/` 覆盖注入 | `SKILL.md` | ✅ **公司路由器实机改过配置**（custom 注入、`clash -t` 预校验、规则命中均验证）；住宅线路待换 |
| **Windows / macOS + Clash Verge Rev（mihomo 内核）** | 手工改配置：单成员代理组、规则顺序、DNS 照搬 | —— | ⚪ 配置模型通用，未逐版本实测 |
| **Mac（Apple 芯片）+ Shadowrocket** | 导入 Clash 配置，代理组与规则大体通用 | —— | ⚪ 可当桌面客户端用，配置能套；TUN / DNS 能力与 mihomo 不完全对等，未实测 |
| **macOS** | launchd 常驻出口守护 | `scripts/claude-guard.sh` | ✅ **本机完整闭环验证**（正常 → 异常触发 → 持续拦截 → 恢复 RECOVER） |
| **Linux（Debian / Ubuntu）** | systemd user / NetworkManager dispatcher | `scripts/claude-guard.sh` | ⚪ 同构方案，脚本逻辑与 macOS 共线，未逐台跑 |
| **Windows 11**（Win10 同机制，未验证） | `schtasks` 登录自启 + PowerShell | `scripts/claude-guard.ps1` | ✅ **Windows 11 24H2 + PowerShell 5.1 实机验证**（`-Check` / `-Watch` / 真杀进程 / 计划任务安装卸载） |
| **手机 / 平板（任何客户端，含 Shadowrocket）** | —— | `references/claude-usage.md` | ❌ 不提供方案，**不要用同一账号在手机上登录** |

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
| **系统层** | 出口 ≠ 锚定 IP 时杀进程 + 阻断域名 | 本仓库 `scripts/` | ✅ 已实测（macOS / Windows 11） |

配套的 16 条防封清单在 `SKILL.md` 里逐条打勾，包含「会话期间不切节点」「同账号不多设备多 IP 同时在线」「支付 / 邮箱地区与 IP 一致」这类非技术项——**很多封号不是配置问题，是行为问题**。

---

## 它治不了什么

先说边界，免得配完发现「怎么还是被封」。平台风控看的是一整张画像，这个仓库只负责其中一格：

| 平台看到的 | 本仓库能不能管 |
| --- | --- |
| 出口 IP 是否固定、是否住宅、有无 DNS / IPv6 / QUIC 泄漏 | ✅ 网络层全管 |
| 出口 IP 在会话中途漂移 | ✅ 单节点 `select` + 出口守护 |
| 浏览器指纹（Canvas / WebGL / 字体 / 时区 / 语言 / UA） | ❌ 路由器看不到，靠浏览器层 |
| 客户端安装 ID、Cookie、登录态 | ❌ 客户端自己上报 |
| 账号行为（同设备多号、支付 / 手机号 / 邮箱地区） | ❌ 属于账号运营 |

准确的说法是：**它让「平台看到的 IP」永远只有一个、且不漂移；它不能阻止平台看见你，也不能让平台认不出你。**

两个现实预期：

- **配置正确不等于免封。** 社区里「软路由用了 7 个月、21 天各封一个号」这类反馈是真实存在的。IP 池信誉、账号历史、内容、支付方式都可能独立触发封禁，本方案降低的是**因网络因素**导致的概率。
- **被封之后不要原地重来。** 同一台设备、同一个 IP 立刻注册新号，大概率连坐。先换 IP、再清浏览器指纹、再等一段时间，顺序别反。

评论区常见的「平台启用了 IP 审查功能 / 会锁定网络设备 ID」这类说法，方向对、概念不对：没有哪个开关叫「IT 审查」，平台做的是持续打分；公网侧也拿不到你的 MAC 地址，路由器后面所有设备的硬件 ID 都留在局域网里。真正能被串起来的是 **IP + 浏览器指纹 + 账号关联**这三样。

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

Windows 用同一份 `KEY=VALUE` 配置，路径换成 `%USERPROFILE%\.config\claude-guard\config`；参数是单横线：`-Check`、`-Watch`、`-Watch -DryRun`、`-Install`、`-Uninstall`；进程名用 `APP_NAME=Claude`；`BLOCK_HOSTS` 在 Windows 上不生效。

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
- **管不到不出网卡的流量**：本机若残留了指向 `127.0.0.1:7890` 之类的代理设置，而那个端口没有程序在听，应用会直接连不上或退回直连——这类流量根本不经过路由器，TUN 规则再正确也拦不住。配完先查一遍：
  ```powershell
  # Windows
  Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer
  netsh winhttp show proxy
  ```
  ```bash
  # macOS（网卡名按实际改）
  networksetup -getwebproxy Wi-Fi
  networksetup -getsecurewebproxy Wi-Fi
  scutil --proxy | grep -i proxy
  ```
  有值但对应端口没程序监听，就说明它该关掉了；有值且真的在跑第三方代理客户端的，先决定留哪个入口，不要两个同时开。

- **Windows 只验证了 PowerShell 5.1 + Windows 11 24H2**：`-Check`、`-Watch`、真实杀进程、`schtasks` 安装 / 卸载均已跑通；**恢复分支（`[RECOVER]`）只在 macOS 上实测过**，Windows 侧代码同构、未单独验证；进程检测按可执行文件名匹配（默认 `Claude`），装成 Store 版后进程名不同时需改 `APP_NAME`，改错会打 `[WARN]` 而不是静默失效；脚本必须保存为 UTF-8 with BOM，否则中文系统的 5.1 会按 GBK 解析中文注释导致语法错误。

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

## 人不在家怎么办（多地点）

家里配好之后，最常见的问题不是「怎么配」，而是**「公司/外地也想用」**。这里有两种做法，安全性差很多。

### 结论先说

**不要用两个静态 IP 并行。** 真正危险的不是 IP 数量，而是**同一个账号在短时间内从两个不同 IP 出现**——这在风控眼里就是「账号被多人共用」，比换 IP 本身严重得多。

判据是这三条，齐了才算相对安全：

| 条件 | 相对安全 | 危险 |
| --- | --- | --- |
| 地理位置 | 同城或同一都市圈（家 ↔ 公司） | 一个美东一个美西，甚至跨国 |
| 使用方式 | 同一台笔记本在两个固定网络间移动 | 两台设备**同时**在线各用一个出口 |
| 切换频率 | 一天一两次，间隔几小时 | 一小时内来回切，或会话中途切换 |

### 推荐：只保留一个出口，回连家里

```
公司/外地笔记本 --(Tailscale)--> 家里的软路由 --> 同一个住宅 IP
```

出口永远只有一个 IP，既没有并发问题，也没有漂移问题，`claude-guard` 的 `EXPECT_IP` 从头到尾不用改。

带宽不是问题：Claude 是文本交互，一轮对话几十 KB，家里的上行完全够。代价只是多绕一跳，通常多 50–150 ms，打字对话基本无感。

**Tailscale 而不是原生 WireGuard**，原因很实际：家用宽带多数是运营商 CGNAT，没有公网 IPv4，原生 WireGuard 需要「公网 IP + DDNS + 端口映射」，你现在未必有。Tailscale 打洞失败还能走 443 中继，酒店和公司网络也大多能通。

出口侧（家里）：

```bash
tailscale up --advertise-exit-node --advertise-routes=192.168.100.0/24
# 然后在 Tailscale 后台该机器的 ... 菜单里 Approve 一次
```

使用侧（笔记本）：

```bash
tailscale up --exit-node=<家里的机器名> --exit-node-allow-lan-access=false
curl -s https://claude.ai/cdn-cgi/trace | grep ip=     # 必须是家里那个住宅 IP
```

`--exit-node-allow-lan-access=false` 是故意的：不要让你在公司网络里顺手连上别人的打印机和 NAS。

### 三个必须确认的泄漏点

启用 exit node 之后，0.0.0.0/0 全部走隧道，外网流量不会自己往外跑。但下面三条会：

1. **IPv6。** 家里那条线没有 IPv6、而笔记本所在网络有，IPv6 就可能绕过隧道直连。验证：

   ```bash
   curl -s https://ipv6.icanhazip.com     # 返回空或失败才是正常的
   ```

   返回公网 IPv6 就是漏了：要么让出口节点带 IPv6，要么在笔记本上关掉 IPv6。

2. **DNS。** 确认解析走的是家里，而不是公司或酒店。最省事的是让出口节点接管 DNS。

3. **本机其他代理。** 最容易漏。笔记本上如果还留着 Clash Verge 的系统代理、或公司 IT 推的强制代理，流量可能先被本机代理接走，根本没进隧道。先确认：

   ```bash
   # macOS
   scutil --proxy | grep -i proxy
   # Windows
   netsh winhttp show proxy
   ```

   有值且端口上有程序在跑，就先决定留哪个入口，**不要两个同时开**。

一个好消息：exit node 断了不会静默回落直连，结果是直接断网。这种失败方式很干脆。

### 非要把笔记本拿到外面直接用

> **⚠ 下面每一条都是「出口可能已经变了但你不知道」的场景，做不到就别在外面临时用主账号。**

- **没连上 exit node 之前，不要打开 Claude。** 先跑 `curl -s https://claude.ai/cdn-cgi/trace | grep ip=`，确认是锚定 IP 再开。
- **不要在公共 WiFi 上直接登录。** 机场、酒店、咖啡店的 WiFi 经常有网页认证，认证过程中 Tailscale 是断的，这时打开 Claude 就是拿真实出口登录。
- **不要用手机热点直接登录。** 热点出口是运营商动态 IP，每次都不一样，这是最典型的异常登录来源。
- **不要在会话中途切换网络。** 正在聊着突然从 WiFi 换到热点，出口当场就变。要换就先关掉页面，等在新网络下确认出口。
- **跨地区出差不要直接登录。** 今天美国、明天日本，同一账号两天内跨洲，比在同一城市挪动可疑得多。
- **连续在外超过几天，宁可不用。** 不登录永远比「换个 IP 继续用」安全，账号不会因为你休息几天出问题。
- **装 `claude-guard` 并把 `EXPECT_IP` 设成家里的 IP。** 忘了开 exit node 时，它能把你拦下来，而不是等你聊到一半才发现。

### 如果坚持两个固定 IP

必须守这六条，缺一条优势就打折：

1. **两个 IP 都要过体检**：trust ≥ 70、`hosting=false`、地区受支持，只满足一个不够。
2. **同一台设备移动**，不要两台设备各待一处。同一台笔记本出现在两个固定网络，是最像真人的形态。
3. **不要同时在线**。一边用完先退出登录或关掉所有标签，隔几分钟再在另一边开。
4. **不要在会话中途切换**，比空闲时切换危险得多。
5. **不要叠加第三个入口**：公司网络本身如果还有代理或 VPN，先确认它没接管 Claude 流量。
6. **两个 IP 最好同城**。同一 ISP 的两个地址最自然；跨 ISP 可以接受，跨州要谨慎。

---

## 目录结构

```
ai-anchor/
├── SKILL.md                       技能主文件：适用场景 / 输入 / A-F 执行流程 / 域名清单 / 13 条防封清单 / 交付要求
├── README.md                      本文件
├── docs/
│   └── topology.svg               拓扑图：设备 → 软路由分流 → 三个去向 → 出口守护
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

**Q：软路由和我电脑上装个代理客户端，到底差在哪？**

**A：** 差在「覆盖范围」和「入口数量」，不是「更安全」：

| | 软路由（本方案） | 本机代理客户端 |
| --- | --- | --- |
| 覆盖设备 | 全屋所有设备，手机 / 平板 / 电视盒子都算 | 只有装了客户端的这一台 |
| 入口数量 | 只有一个 TUN 入口 | 客户端 + 系统代理容易双开 |
| UDP / QUIC | 一起接管 | 很多客户端只代理 TCP，QUIC 直接漏 |
| DNS | 路由器统一解析，AI 域名强制远端 DoH | 各设备各自解析，容易漏 |
| 忘开就漏 | 不会，开机即在 | 常见，人一忘就是真实出口 |
| 换网络 | 换 WiFi / 接热点仍走同一出口 | 要重开，且经常忘记 |

只用一台电脑、只在这台电脑上用 Claude，本机客户端也够用；只要家里还有第二台设备，或者你会带着笔记本到处走，路由器才是那个「不需要你记得」的方案。

**Q：评论区说用软路由也照样被封，那还有必要配吗？**

**A：** 有必要，但别把它当免死金牌。本方案管的是「出口 IP 固定、不漂移、不泄漏」，管不了浏览器指纹和账号行为。配置正确也会因为 IP 池信誉、账号历史、支付方式被单独触发封禁。边界写在 [它治不了什么](#它治不了什么) 里，先看完再决定预期。

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
- 本仓库以 **MIT** 许可开源，`SKILL.md`、参考文档与守护脚本均可自由使用、修改、分发。Claude / ChatGPT / Gemini 的服务条款由各家自行解释，**因使用本方案产生的账号风险由使用者自行承担**。
