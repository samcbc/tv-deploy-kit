#!/system/bin/sh
# 轮询 AdbInstallActivity 并点「继续安装」按钮（1920x1080 下约 x=1126 y=696）
i=0
while [ $i -lt 60 ]; do
  if dumpsys window windows 2>/dev/null | grep -q "AdbInstallActivity"; then
    input tap 1126 696
    echo "tapped at $i" >> /data/local/tmp/inst.log
  fi
  i=$((i+1))
  sleep 0.2
done
