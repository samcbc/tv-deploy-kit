#!/system/bin/sh
# 透明代理规则：IPv4 + IPv6 都劫持
PORT_REDIR=7892
PORT_DNS=1053
# 代理服务器 IP：必须直连、不能走重定向，否则回环。留空则跳过该条规则。
PROXY_SERVER=${PROXY_SERVER:-}

echo "[1] 清空旧规则"
iptables  -t nat -F OUTPUT 2>/dev/null || true
ip6tables -t nat -F OUTPUT 2>/dev/null || true

echo "[2] IPv4"
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner 0 -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 192.168.0.0/16 -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.0/8 -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 10.0.0.0/8 -j RETURN
if [ -n "$PROXY_SERVER" ]; then
    iptables -t nat -A OUTPUT -p tcp -d "$PROXY_SERVER" -j RETURN
fi
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $PORT_DNS
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $PORT_DNS
iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports $PORT_REDIR

echo "[3] IPv6"
ip6tables -t nat -A OUTPUT -p tcp -m owner --uid-owner 0 -j RETURN
ip6tables -t nat -A OUTPUT -p tcp -d fd00::/8 -j RETURN
ip6tables -t nat -A OUTPUT -p tcp -d fe80::/10 -j RETURN
ip6tables -t nat -A OUTPUT -p tcp -d ::1/128 -j RETURN
ip6tables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $PORT_DNS
ip6tables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $PORT_DNS
ip6tables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports $PORT_REDIR

echo "[4] 结果"
iptables  -t nat -S OUTPUT
echo ---
ip6tables -t nat -S OUTPUT
