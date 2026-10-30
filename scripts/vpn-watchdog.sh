#!/system/bin/sh
# 代理看护：每 20 秒检查一次，缺什么补什么
#  1) mihomo 进程没了 → 重启
#  2) nat OUTPUT 规则被清 → 重新下发
#  3) IPv6 出站没封 → 重新封（netd 会在网卡变化时把 IPv6 恢复回来）
LOG=/data/local/tmp/watchdog.log
REDIR_RULES=8
echo $$ > /data/local/tmp/watchdog.pid

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; }

apply_rules() {
    sh /data/local/tmp/redir-on2.sh >/dev/null 2>&1
    ip6tables -F OUTPUT 2>/dev/null
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -j REJECT 2>/dev/null
}

log "watchdog 启动 (pid $$)"
last_state=""

while true; do
    changed=0

    # 1) 进程
    if [ -z "$(pidof mihomo)" ]; then
        log "mihomo 不在，重启"
        cd /data/local/tmp || exit 1
        setsid /data/local/tmp/mihomo -d /data/local/tmp -f /data/local/tmp/mihomo-redir.yaml \
            >> /data/local/tmp/mihomo.log 2>&1 < /dev/null &
        sleep 4
        log "mihomo 已启动 pid=$(pidof mihomo)"
        changed=1
    fi

    # 2) iptables 规则数量
    n=$(iptables -t nat -S OUTPUT 2>/dev/null | grep -c REDIRECT)
    if [ "$n" -lt 3 ]; then
        log "nat 规则缺失(=$n)，重新下发"
        apply_rules
        changed=1
    fi

    # 3) IPv6 是否被封
    if ! ip6tables -S OUTPUT 2>/dev/null | grep -q REJECT; then
        log "IPv6 未被封，重新封"
        ip6tables -F OUTPUT 2>/dev/null
        ip6tables -A OUTPUT -o lo -j ACCEPT
        ip6tables -A OUTPUT -j REJECT 2>/dev/null
        changed=1
    fi

    # 4) 每 5 分钟写一次心跳
    ts=$(date +%M)
    if [ "$changed" = "0" ] && [ $((ts % 5)) -eq 0 ] && [ "$last_state" != "$ts" ]; then
        log "心跳 mihomo=$(pidof mihomo) rules=$n"
        last_state=$ts
    fi

    sleep 20
done
