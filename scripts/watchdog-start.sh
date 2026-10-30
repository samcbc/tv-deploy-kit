#!/system/bin/sh
# 看护启动器：本身不常驻，只负责把 vpn-watchdog.sh 拉起来（带 pidfile 去重）
PIDF=/data/local/tmp/watchdog.pid
if [ -f "$PIDF" ]; then
    old=$(cat "$PIDF" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        echo "watchdog 已在运行 pid=$old"
        exit 0
    fi
fi
setsid sh /data/local/tmp/vpn-watchdog.sh >/dev/null 2>&1 < /dev/null &
sleep 2
new=$(cat "$PIDF" 2>/dev/null)
echo "watchdog 已启动 pid=${new:-未知}"
