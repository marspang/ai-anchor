# 网络隔离加固（可选，建议做）

目标：让机器只有一条可信出口，避免自动连上手机热点 / 公共 WiFi 后泄漏真实 IP。

## 一、出口守卫（最重要）

在设备上放一个校验脚本，每次用 Claude 前跑一次，或做成开机自启。

### macOS / Linux

```bash
#!/usr/bin/env bash
EXPECT="<ANCHOR_IP>"   # 换成锚定的住宅 IP
CUR=$(curl -s --max-time 8 https://claude.ai/cdn-cgi/trace | awk -F= '/^ip=/{print $2}')
if [ "$CUR" != "$EXPECT" ]; then
  echo "❌ 出口异常：当前 ${CUR:-无}，应为 $EXPECT —— 不要使用 Claude"
  exit 1
fi
echo "✅ 出口正常：$CUR"
```

保存为 `~/bin/egress-guard`，加执行权限。macOS 可再用 launchd 每小时跑一次并弹通知。

### Windows（PowerShell）

```powershell
$expect = "<ANCHOR_IP>"
$cur = ((Invoke-WebRequest -UseBasicParsing "https://claude.ai/cdn-cgi/trace" -TimeoutSec 8).Content -split "`n" |
        Where-Object { $_ -like "ip=*" }) -replace "ip=", ""
if ($cur -ne $expect) { Write-Host "❌ 出口异常：$cur，应为 $expect" -ForegroundColor Red; exit 1 }
Write-Host "✅ 出口正常：$cur" -ForegroundColor Green
```

## 二、忘掉多余 WiFi / 关闭自动连接

### macOS

```bash
# 列出已保存的 WiFi
networksetup -listpreferredwirelessnetworks en0

# 删除某个（防止自动连）
sudo networksetup -removepreferredwirelessnetwork en0 "手机热点名称"
```

- 「自动加入热点」只能 GUI 关：系统设置 → Wi-Fi → 自动加入热点 → 从不。
- 查看 Wi-Fi 设备名：`networksetup -listallhardwareports`。

### Windows（管理员 PowerShell）

```powershell
netsh wlan show profiles
netsh wlan delete profile name="手机热点名称"
# 保留但改为手动连接
netsh wlan set profileparameter name="手机热点名称" connectionmode=manual
```

- 关闭热点自动连接：设置 → 网络和 Internet → WLAN → 关闭「自动连接热点」。

### Linux

```bash
nmcli -t -f NAME,TYPE connection show
nmcli connection delete "手机热点名称"
nmcli connection modify "手机热点名称" connection.autoconnect no
```

## 三、台式机：直接关掉无线网卡（最彻底）

### macOS

```bash
sudo networksetup -setairportpower en1 off     # en1 用上一步查到的 Wi-Fi 设备名
```

### Windows（管理员）

```powershell
netsh interface show interface
netsh interface set interface "Wi-Fi" admin=disable
```

### Linux

```bash
nmcli radio wifi off
```

## 四、笔记本外出时的处理

- 保留 WiFi，但不要让它自动连非信任网络：把已知热点设为 manual，或干脆删除。
- 外出想用 Claude：手机热点 + 笔记本代理，**先跑出口守卫**，通过再用。
- 没有代理就不要开 Claude，也不要手机 App 登同一账号。

## 五、做完的自查

1. 关掉代理，运行守卫脚本，必须报「出口异常」（说明它真的在检查）。
2. 打开代理，再跑一次，必须报「出口正常」。
3. 连一次手机热点，确认不会自动连上（或连上后守卫会拦）。
