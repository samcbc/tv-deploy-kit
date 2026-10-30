#!/system/bin/sh
# 一键开启透明代理（重启后跑这一次就够）
# 顺序：起 mihomo → 上规则 → 封 IPv6 出站 → 起看护
cd /data/local/tmp || exit 1

echo "[1/4] 启动 mihomo"
pkill -x mihomo 2>/dev/null
sleep 1
setsid /data/local/tmp/mihomo -d /data/local/tmp -f /data/local/tmp/mihomo-redir.yaml \
    >> /data/local/tmp/mihomo.log 2>&1 < /dev/null &
sleep 3
echo "    pid = $(pidof mihomo)"

echo "[2/4] 下发 iptables 透明代理规则"
sh /data/local/tmp/redir-on2.sh >/dev/null 2>&1
echo "    nat 规则数 = $(iptables -t nat -S OUTPUT | grep -c REDIRECT)"

echo "[3/4] 封掉 IPv6 出站（否则 DNS 会绕过劫持；不影响网卡，不需要断电）"
ip6tables -F OUTPUT 2>/dev/null
ip6tables -A OUTPUT -o lo -j ACCEPT
ip6tables -A OUTPUT -j REJECT 2>/dev/null
echo "    ip6tables: $(ip6tables -S OUTPUT | tail -1)"

echo "[4/4] 启动看护进程（进程挂了/规则丢了会自动补）"
sh /data/local/tmp/watchdog-start.sh

echo "--- 完成，验证 ---"
echo -n "mihomo: "; pidof mihomo
echo -n "watchdog: "; cat /data/local/tmp/watchdog.pid 2>/dev/null
echo -n "DNS: "; ping -c 1 -W 3 www.google.com 2>&1 | head -1
