#!/system/bin/sh
# 一键关闭：撤规则 + 停 mihomo + 恢复 IPv6
iptables  -t nat -F OUTPUT 2>/dev/null
ip6tables -t nat -F OUTPUT 2>/dev/null
pkill -x mihomo 2>/dev/null
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.eth0.disable_ipv6=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.wlan0.disable_ipv6=0 >/dev/null 2>&1
echo "已关闭：nat 规则已清空，mihomo 已停，IPv6 已恢复"
iptables -t nat -S OUTPUT
