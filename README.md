# 创维/酷开电视 ROOT + CleanYourTV 桌面 部署手册

> **免责声明**
> 本仓库只记录在一台**自己拥有**的电视上做过的事，供同型号机主参考。
> 改 boot 分区、打内核补丁属于高风险操作，**可能变砖、失去保修、并使设备失去安全性**
> （补丁会让所有进程的 capability 检查通过，等于任何 App 都能提权到 root）。
> 请先完整备份原厂镜像，对自己设备的后果自行负责。
>
> **第三方组件**
> 桌面 APK（`apk/tvhome.apk`）编译自 [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv)，
> 版权与许可以该项目为准（见其仓库 LICENSE），本仓库仅提供自编译产物与安装说明。
> 代理由 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 提供，遵循其 GPL-3.0 许可。
>
> **不含任何凭据**：本仓库已移除代理服务器地址、UUID、签名密钥等敏感内容；
> `scripts/redir-on2.sh` 的 `PROXY_SERVER` 需使用者自行填写。

适用机型：`sky848_9s60` / `7S77_K30`（创维/酷开，Android 8.0，内核 4.9.44+ arm64，用户态 armeabi-v7a）
本手册在同一台机器上全流程实测通过；换电视时**内核补丁的地址必须重新推导**（见 3.6）。

---

## 0. 这套方案干了什么

| 能力 | 实现方式 | 是否可逆 |
|---|---|---|
| root | 借 uid-1000 的 provider 通道改 boot 分区权限 → 给内核 `cap_capable` 打 8 字节补丁 → dd 回 | 可（dd 回原厂 boot.img） |
| 换桌面 | 编译 CleanYourTV 桌面（`com.gathin.tvhome`）+ 改写 Home shim 指向它 | 可（shim 改回当贝/原生） |
| 去广告 | `pm disable-user` 停用（不卸载、不写系统分区） | 可（`pm enable`） |
| 翻墙 | mihomo root 守护进程 + iptables 透明代理 + 看护进程 | 可（vpn-off.sh） |

**风险提示**：改 boot 分区是唯一有变砖风险的一步。**必须先完整 dump 原厂 boot.img 并保存到 PC**，
再动手。recovery 分区不受影响，最坏情况可以用 U 盘恢复刷回。

---

## 1. 准备

### 1.1 PC 端

```bash
adb          # platform-tools，用于连接与推送
python3      # 解析 boot 头、打补丁脚本用
uv           # 建独立 venv 装 vmlinux-to-elf（Python 3.14 下 minilzo 编译失败，需 3.12）
zig          # 交叉编译电视端原生程序（aarch64 / armv7 musl 静态）
```

电视端原生程序用 zig 交叉编译，**不用装 NDK**：

```bash
zig cc -target aarch64-linux-musl -O2 -static -o su su.c        # 64 位（本机内核支持 64 位进程）
zig cc -target arm-linux-musleabihf -O2 -static -o probe probe.c # 32 位
```

### 1.2 电视端前提（逐条确认，缺一不可）

```bash
adb connect <TV_IP>:5555
adb shell getprop ro.build.type          # user（production 构建，adb root 不可用）
adb shell getprop ro.debuggable          # 0
adb shell getprop ro.secure              # 1
adb shell cat /proc/cmdline | tr ' ' '\n' | grep -E 'SECURITY|selinux'
#   期望：SECURITY=OFF  androidboot.selinux=permissive
adb shell getenforce                     # Permissive
adb shell getprop | grep -iE 'verity|vbmeta|verified'   # 期望：无输出（无 AVB / 无 dm-verity）
```

若存在 `dm-verity` / AVB / `ro.boot.verifiedbootstate=green`，**本方案不适用**（改 boot 会校验失败）。

---

## 2. 工程结构（本部署包）

```
DEPLOY_KIT/
├── apk/
│   ├── tvdump.apk     # 借 uid1000 执行 execLinuxCmd（改块设备权限）—— root 第一步的关键
│   ├── shim.apk       # Home 中转（com.ccos.tv.homepage），把 Home 指向目标桌面
│   └── tvhome.apk     # CleanYourTV 桌面（com.gathin.tvhome v3.2，从源码编译）
├── bin/
│   ├── su             # 提权工具（aarch64 静态）：setuid(0) 后 exec sh
│   └── roottest       # 提权验证（setuid(0) 并打印 uid）
├── scripts/
│   ├── inst.sh        # 电视端轮询点「继续安装」（绕过 5 秒自动拒绝）
│   ├── vpn-on.sh      # 一键开代理（mihomo + iptables + 封 IPv6 + 看护）
│   ├── vpn-off.sh     # 一键关代理
│   ├── redir-on2.sh   # 只下发 iptables 规则
│   ├── vpn-watchdog.sh# 看护：mihomo 挂了/规则丢了自动补
│   └── watchdog-start.sh # 看护启动器（pidfile 去重）
├── lists/             # 停用清单（4 批，共 26 个包）
├── tools/             # boot 解析 / 符号定位 / 打补丁 / 校验 脚本
└── fw/kernel.config   # 本机内核配置（对照用）
```

**源码位置（PC）**：

| 组件 | 源码 |
|---|---|
| tvdump | `~/tvroot/tvdump/`（`build.sh` 一键编译） |
| shim | `~/tvroot/shim/`（`build.sh` 一键编译） |
| 桌面 | `~/tvroot/cleanyourtv/launcher/`（Gradle 工程） |

---

## 3. 第一步：拿 root

> 核心思路：`adb root` 在 production 构建上永远不可用。但酷开有个 uid-1000 的
> ContentProvider 通道（`execLinuxCmd`）能执行 `chmod`，而 **boot 分区的属主正好是 system(uid 1000)**
> —— 于是可以 chmod 块设备 → dd 出 boot.img → 打内核补丁 → dd 回去。

### 3.1 装 tvdump.apk

```bash
adb push apk/tvdump.apk /data/local/tmp/tvdump.apk
# 新装包会被 AdbInstallActivity 拦（5 秒无人点「继续安装」就 auto_refuse），必须电视端轮询点击
adb push scripts/inst.sh /data/local/tmp/inst.sh
adb shell "chmod 755 /data/local/tmp/inst.sh"
adb shell "nohup /data/local/tmp/inst.sh >/dev/null 2>&1 &"
adb shell "pm install -r /data/local/tmp/tvdump.apk"     # 期望 Success
```

### 3.2 用 tvdump 改 boot 分区权限

`tvdump` 从 `/data/local/tmp/cmd.txt` 读命令，每行 `cmd编号|参数`：

```bash
printf '0|666 /dev/block/mmcblk0p6\n' > cmd.txt     # 0=CHMOD，路径换成你自己的 boot 分区
adb push cmd.txt /data/local/tmp/cmd.txt
adb shell "chmod 644 /data/local/tmp/cmd.txt"
adb shell "am force-stop com.hermes.tvdump; am start -n com.hermes.tvdump/.MainActivity"
adb shell "ls -l /dev/block/mmcblk0p6"              # 期望 brw-rw-rw-
```

**调用形状必须严格一致**（缺一个就静默失败）：

```java
Bundle inner = new Bundle();
inner.putInt("cmd", 0);                            // 0=CHMOD 1=CP 2=MKDIR 3=MOUNT 4=MV
inner.putString("param", "666 /dev/block/mmcblk0p6");  // 5=PING 6=PM_INSTALL 7=PM_UNINSTALL 8=REBOOT 9=SYNC
Bundle extras = new Bundle();
extras.putBoolean("method_set", true);             // 必须 true，false 只打日志不执行
extras.putParcelable("param", inner);              // 必须 Parcelable 的 Bundle，传 String 会 ClassCastException
cr.call(Uri.parse("content://com.tianci.provider"), "COMMON", "execLinuxCmd", extras);
```

> 该通道是 `Runtime.exec` 的 argv 形式，**不能注入 shell**（`;` 当文件名，返回 ret=1）。

找 boot 分区：

```bash
adb shell ls -l /dev/block/platform/*/by-name/ | grep -E 'boot|recovery'
# 本机：boot = /dev/block/mmcblk0p6（属主 system drmrpc，可被 uid1000 chmod）
```

### 3.3 dump boot.img

```bash
adb shell "dd if=/dev/block/mmcblk0p6 of=/data/local/tmp/boot_orig.img bs=1048576"
adb pull /data/local/tmp/boot_orig.img boot.img
sha256sum boot.img        # 记下来，回滚时要用
```

**立刻在电视里也留一份**：`adb push boot.img /data/local/tmp/boot_orig.img`

### 3.4 解析 boot 头

```bash
python tools/parse_boot.py boot.img
```

输出关键字段（本机示例）：

```
magic: b'ANDROID!'
kernel_size    = 15794688     kernel 偏移 0x800（page_size=2048）
ramdisk_size   = 1850568
cmdline        = buildvariant=user
kernel 前 16 字节: 4d5a...    ← "MZ"，MStar 封装，未压缩
```

同时会写出 `kernel_raw.bin`。确认里面能搜到 `Linux version 4.9.44`（说明内核未压缩，可直接打补丁）。

### 3.5 生成符号表

```bash
# 内核配置（IKCONFIG）应能看到：
#   CONFIG_KALLSYMS=y          → 有符号
#   CONFIG_RANDOMIZE_BASE 未设置 → KASLR 关闭（关键！否则地址不固定）
#   CONFIG_ARM64=y

uv venv --python 3.12 .venv
uv pip install --python .venv/Scripts/python.exe vmlinux-to-elf
.venv/Scripts/vmlinux-to-elf.exe kernel_raw.bin vmlinux.elf
```

得到 `vmlinux.elf`（本机 39,479 个符号，基址 `0xffffff8008080000`）。

### 3.6 定位要打补丁的函数（换电视必须重做这一步）

```bash
python tools/locate_patch.py
```

它做的事：

1. 从 `vmlinux.elf` 的符号表里取 `cap_capable` 的地址
2. **不用 ELF 偏移直接换算**（vmlinux-to-elf 有 0x1c0 头部偏移，直接算会错）
3. 取该符号处的**前 16 字节作为指纹**，在 boot.img 里做**字节搜索**，要求**唯一命中**
4. 校验 `0xffffff8008080000 + (命中偏移 - 0x800)` 是否等于符号地址

本机实测：

```
cap_capable = 0xffffff8008454e04
指纹（原始）: fd7bbda9 5f340071 fd030091 f30b00f9   (stp x29,x30,[sp,#-0x30]! / cmp / mov / str)
boot.img 内偏移 = 0x3d5604（唯一命中）
```

### 3.7 打补丁

```bash
python tools/make_patch.py      # 生成 boot_patched.img
python tools/verify_patch.py    # 校验结构与反汇编
```

补丁内容：把 `cap_capable()` 首指令改成 `mov w0,#0 ; ret`，即**恒返回 0（有权限）**。
这样任何进程调 `setuid(0)` 都会被放行。

```
原始: fd7bbda9 5f340071 fd030091 f30b00f9
补丁: 00008052 c0035fd6        ← mov w0,#0 ; ret
```

校验输出应为：

```
差异字节数: 8（仅 0x3d5604 起 8 字节）
结构: kernel/ramdisk 大小完全一致，页大小一致
反汇编: stp x29,x30,[sp,#-0x30]!  →  mov w0,#0 ; ret
```

### 3.8 刷入并验证

```bash
adb push boot_patched.img /data/local/tmp/
adb shell "dd if=/data/local/tmp/boot_patched.img of=/dev/block/mmcblk0p6 bs=1048576"
# 读回校验（必须与补丁文件 sha256 完全一致，不一致绝不能重启）
adb shell "dd if=/dev/block/mmcblk0p6 of=/data/local/tmp/rb.img bs=1048576; sha256sum /data/local/tmp/rb.img"
adb shell "sync; reboot"
```

重启后：

```bash
adb push bin/roottest /data/local/tmp/; adb shell "chmod 755 /data/local/tmp/roottest"
adb shell "/data/local/tmp/roottest"
# 期望：setuid(0) -> 0 (OK) / after : uid=0 euid=0 / ROOT OK
```

### 3.9 装 su

```bash
adb push bin/su /data/local/tmp/su
adb shell "chmod 755 /data/local/tmp/su"
adb shell "cd /data/local/tmp && ./su -c id"     # uid=0(root)
```

> **git-bash 坑**：直接写 `adb shell "/data/local/tmp/su -c id"` 会被 MSYS 改写成
> `C:/msys64/data/local/tmp/su`。用 `cd /data/local/tmp && ./su ...` 的形式最稳。

### 3.10 回滚

```bash
adb shell "cd /data/local/tmp && ./su -c 'dd if=/data/local/tmp/boot_orig.img of=/dev/block/mmcblk0p6 bs=1048576; sync; reboot'"
```

---

## 4. 第二步：装 CleanYourTV 桌面

### 4.1 编译（如果直接用包里的 tvhome.apk 可跳过）

需求：`compileSdk 34 / minSdk 26`，纯 Java 无 native 库，armv7 可直接跑。

本机原始 SDK 没有 34，需要补：

```bash
# 注意：platform-34_r03.zip 是 404，真实文件名带 ext
curl -L -o platform34.zip https://dl.google.com/android/repository/platform-34-ext7_r03.zip
curl -L -o bt34.zip       https://dl.google.com/android/repository/build-tools_r34-windows.zip
unzip -q platform34.zip -d $SDK/platforms/          # 解出 android-34/
unzip -q bt34.zip -d $SDK/build-tools/              # 解出 android-14/，需改名
mv $SDK/build-tools/android-14 $SDK/build-tools/34.0.0
```

`launcher/local.properties` 写 `sdk.dir=I:/Android/Sdk`（**正斜杠**，反斜杠会被当转义）。

```bash
cd launcher
JAVA_HOME=<JDK17> ANDROID_HOME=<SDK> \
GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=10810 \
             -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=10810" \
./gradlew assembleRelease --console=plain
# 产物：app/build/outputs/apk/release/app-release.apk（约 574KB）
```

### 4.2 安装

```bash
adb push apk/tvhome.apk /data/local/tmp/tvhome.apk
adb shell "pm enable com.coocaa.os.manager"    # 关键！见下方说明
adb shell "nohup /data/local/tmp/inst.sh >/dev/null 2>&1 &"
adb shell "pm install -r /data/local/tmp/tvhome.apk"    # 期望 Success
```

> **反直觉的坑**：如果之前为了防后台杀进程停用了 `com.coocaa.os.manager`，
> `pm install` 会一直返回 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`
> —— 因为**安装确认弹窗就住在它里面**。装包前必须先 enable。

### 4.3 设为默认桌面（必须改 shim，改属性无效）

酷开开机时会把 `persist.service.homepage.pkg` **强制改回已存在的 shim 包**
（`com.ccos.tv.homepage`），所以直接 setprop 到新桌面重启后就丢。

正确做法：**让 shim 去拉起新桌面**（三级回落防黑屏）：

```java
// shim 的 LaunchActivity
if (!start("com.gathin.tvhome", "com.gathin.tvhome.MainActivity")) {
    if (!start("com.dangbei.tvlauncher", "com.dangbei.launcher.ui.main.MainActivity")) {
        start("com.tianci.movieplatform", "com.coocaa.homepage.vast.HomePageActivity");
    }
}
```

```bash
adb push apk/shim.apk /data/local/tmp/shim.apk
adb shell "pm install -r /data/local/tmp/shim.apk"       # 已装过则直接 Success
adb shell "cd /data/local/tmp && ./su -c 'setprop persist.service.homepage.pkg com.ccos.tv.homepage; setprop persist.service.homepage.cls com.ccos.tv.homepage.LaunchActivity'"
adb shell "cmd package set-home-activity com.gathin.tvhome/.MainActivity"
```

验证：按 Home 键 → 应进入 CleanYourTV 桌面；重启后依然有效（开机停在 `com.skyworth.tv`，按一次 Home 即进桌面）。

---

## 5. 第三步：停用式清理（可选，可逆）

```bash
for f in lists/*.txt; do
  while read -r pkg _; do
    [ -z "$pkg" ] && continue
    case "$pkg" in \#*) continue;; esac
    adb shell "pm disable-user --user 0 $pkg"
  done < "$f"
done
adb shell "pm list packages -d | wc -l"     # 本机：26
```

### 5.1 绝对不能停的（会导致电视不可用）

```
com.skyworth.tv            信号源/调谐/电视画面
com.tianci.system          Home 键 / 输入源面板 / execLinuxCmd 通道
com.coocaa.os.ccosservice  系统核心服务
com.skyworth.setting       设置
com.skyworth.android.skyRMService  遥控
com.coocaa.os.manager      **安装弹窗宿主**（停了就装不了 APK）
```

### 5.2 投屏相关（**别停**，本机踩过坑）

```
swaiotos.channel.iot       小维互联/跨设备投屏通道（系统包，shell 改不了状态，需 root）
com.coocaa.skycast.tool    投屏组件
com.coocaa.sky.ccapi       投屏 API
com.coocaa.miracast        Miracast
```

> 停了投屏通道后，手机就再也发现不了电视。恢复：`su -c 'pm enable swaiotos.channel.iot'`（其余可不带 su）。

---

## 6. 第四步：透明代理（可选，让 YouTube 能用）

> 前提：本机 ROM 会杀 App（VpnService 类应用切前台即死），所以**不能用 Clash 类 App**，
> 必须跑 root 守护进程。实测 setsid 过的守护进程能长期存活。

### 6.1 装 mihomo

```bash
# 32 位用户态必须 armv7；GitHub 直连不通时用镜像 https://ghfast.top/<原地址>
curl -L -o mihomo.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-android-armv7-v1.19.33.gz
gunzip mihomo.gz
adb push mihomo /data/local/tmp/mihomo && adb shell "chmod 755 /data/local/tmp/mihomo"
adb shell "/data/local/tmp/mihomo -v"     # Mihomo Meta v1.19.33 android arm
```

配置要点（`mihomo-redir.yaml`）：`redir-port: 7892`、DNS `listen 0.0.0.0:1053`、`tun.enable: false`，
代理节点写 vless/trojan 等。**geoip 数据库不能联网下载**，从已装的 Clash 类 App 里拷：

```bash
cp /data/data/com.github.metacubex.clash.meta/files/clash/geoip.metadb /data/local/tmp/
```

### 6.2 一键开关

```bash
adb push scripts/*.sh /data/local/tmp/ && adb shell "chmod 755 /data/local/tmp/*.sh"
adb shell "cd /data/local/tmp && ./su -c 'sh /data/local/tmp/vpn-on.sh'"    # 开
adb shell "cd /data/local/tmp && ./su -c 'sh /data/local/tmp/vpn-off.sh'"   # 关
```

### 6.3 两个必踩的坑

1. **DNS 不走 netfilter**：本机 `net.dns1` 是 IPv6（`2402:4e00::`），DNS 查询根本不经过 iptables
   的 OUTPUT 链（计数器为 0）。**必须封掉 IPv6 出站**才会回落到 IPv4 DNS 并被 UDP 53 重定向抓住：
   ```bash
   ip6tables -F OUTPUT; ip6tables -A OUTPUT -o lo -j ACCEPT; ip6tables -A OUTPUT -j REJECT
   ```
   不要用 `sysctl disable_ipv6`（会重置网卡、adb 断连，且 netd 会在网卡变化时把 IPv6 又打开）。
2. **`pkill -f <关键字>` 会把自己杀掉**（adb shell 命令行里就含这个关键字）。一律用 `pkill -x mihomo`
   或 pidfile 判活。

### 6.4 验证

```bash
adb shell "ping -c1 www.google.com" | head -1        # 期望 198.18.x.x（fake-ip，劫持成功）
adb shell "echo -e 'GET /proxies/<节点名>/delay?timeout=8000&url=https://www.youtube.com HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n' | toybox nc -w 25 127.0.0.1 9090"
# 期望 {"delay":xxx}
```

---

## 7. 完工检查清单

```bash
adb shell "cd /data/local/tmp && ./su -c id"                 # uid=0(root)
adb shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1"
                                                             # com.gathin.tvhome/.MainActivity
adb shell "pm list packages | grep com.gathin.tvhome"        # 桌面已装
adb shell "pm list packages -d | wc -l"                      # 停用数量
adb shell "cd /data/local/tmp && ./su -c 'pidof mihomo'"     # 代理在跑（如启用）
adb shell "cd /data/local/tmp && ./su -c 'iptables -t nat -S OUTPUT | grep -c REDIRECT'"   # 3
adb shell "ping -c1 www.google.com" | head -1                # 198.18.x.x
```

---

## 8. 排错速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `adb root` 被拒 | production 构建 | 正常，走内核补丁路线 |
| `pm install` → `INSTALL_FAILED_USER_RESTRICTED` | AdbInstallActivity 5 秒自动拒绝，或 os.manager 被停用 | 跑 `inst.sh` 轮询点击；`pm enable com.coocaa.os.manager` |
| 改了 Home 属性重启就丢 | 酷开开机强制改回 shim 包 | 改 shim 指向，别改属性 |
| 装完桌面 Home 还是当贝 | shim 没更新 | 重编 shim 并 `pm install -r` |
| 代理切到别的应用就没了 | ROM 杀 App（VpnService 应用） | 用 mihomo root 守护进程，不用 App |
| 代理时好时坏、DNS 解析成奇怪 IP | IPv6 绕过劫持 | `ip6tables -A OUTPUT -j REJECT` |
| 手机发现不了电视 | 投屏通道被停用 | `su -c 'pm enable swaiotos.channel.iot'` + 其余两个 |
| `su` 提示 `C:/msys64/data/...` not found | git-bash 路径改写 | `cd /data/local/tmp && ./su ...` |
| 内核 oops 后电视卡死不动 | `panic_on_oops=1` + `panic=0` | 手动断电重启 |

---

## 9. 附：本机（7S77_K30）实测数值

```
boot 分区            /dev/block/mmcblk0p6（20,971,520 字节，属主 system drmrpc）
page_size            2048
kernel 偏移/大小      0x800 / 15,794,688（MZ 开头，未压缩）
ramdisk 大小         1,850,568
内核基址             0xffffff8008080000
cap_capable          0xffffff8008454e04   → boot.img 偏移 0x3d5604
补丁                 00008052 c0035fd6   (mov w0,#0 ; ret)
原厂 boot sha256     4f79891ad84ba8b1df3e466510ac93ca66d598025dafd0ccd274b863dbba1bb6
补丁 boot sha256     cad646f998963c5d726b5f1fbb2c6633f26f91e8aa48132a8e88851847b16b44

其他符号（备用）：
commit_creds         0xffffff80080e29f0
prepare_kernel_cred  0xffffff80080e2eb0
modprobe_path        0xffffff8008ea41d0
binder_poll          0xffffff8008761e14
```

> 换电视时这些数值**全部无效**，必须按 3.4–3.7 重新推导。

---

## 10. 已知未解决

- **标准 DLNA 不可用**：本机没有 SSDP 服务（关掉代理后 1900 端口依然不存在，单播/组播探测均无响应）。
  原生只支持自家协议（swaiotos/icast）+ Miracast。Kodi 的 UPnP 开启后 1900 会监听但不应答 M-SEARCH。
- **真 GMS 装不了**：必须是 `/system/priv-app` 特权应用，而 `/system` remount 恒 EBUSY
  （块设备没锁、mount 能力有、内核无 overlayfs）。要做得离线改 ext4 镜像再 dd。
- **代理开机不自启**：重启后需手动跑一次 `vpn-on.sh`（改 ramdisk 加 init 服务可实现，但需重新打包 ramdisk）。
