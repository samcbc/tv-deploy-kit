#!/usr/bin/env bash
# 用 Android SDK 自带工具链编译 shim APK（不依赖 gradle / 网络）
set -euo pipefail
BT="D:/Android/android-sdk/build-tools/32.0.0"
ANDROID_JAR="D:/Android/android-sdk/platforms/android-33/android.jar"
JDK="I:/Android/sdk/extras/jdk-17/jdk-17.0.13+11"
cd "$(dirname "$0")"

echo "== 1. 清单/资源链接 =="
rm -rf out && mkdir -p out/classes out/dex
"$BT/aapt2.exe" link -o out/base.apk --manifest AndroidManifest.xml -I "$ANDROID_JAR" || true
ls -l out/base.apk

echo "== 2. javac =="
find src -name '*.java' > out/sources.txt
"$JDK/bin/javac.exe" -nowarn -encoding UTF-8 -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d out/classes @out/sources.txt
find out/classes -name '*.class'

echo "== 3. d8 -> classes.dex =="
"$JDK/bin/java.exe" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 \
  --lib "$ANDROID_JAR" --min-api 26 --output out/dex $(find out/classes -name '*.class')
ls -l out/dex

echo "== 4. 打包 dex 进 apk =="
cp out/base.apk out/unsigned.apk
(cd out/dex && "$JDK/bin/jar.exe" uf ../unsigned.apk classes.dex)
unzip -l out/unsigned.apk

echo "== 5. zipalign =="
"$BT/zipalign.exe" -f -p 4 out/unsigned.apk out/aligned.apk

echo "== 6. 签名 =="
if [ ! -f debug.keystore ]; then
  "$JDK/bin/keytool.exe" -genkeypair -keystore debug.keystore -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" 2>&1 | tail -2
fi
"$JDK/bin/java.exe" -jar "$BT/lib/apksigner.jar" sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --min-sdk-version 26 --out out/shim.apk out/aligned.apk
"$JDK/bin/java.exe" -jar "$BT/lib/apksigner.jar" verify --print-certs out/shim.apk | head -5
ls -l out/shim.apk
