#!/usr/bin/env bash
set -euo pipefail
BT="D:/Android/android-sdk/build-tools/32.0.0"
ANDROID_JAR="D:/Android/android-sdk/platforms/android-33/android.jar"
JDK="I:/Android/sdk/extras/jdk-17/jdk-17.0.13+11"
cd "$(dirname "$0")"
rm -rf out && mkdir -p out/classes out/dex
"$BT/aapt2.exe" link -o out/base.apk --manifest AndroidManifest.xml -I "$ANDROID_JAR"
find src -name '*.java' > out/sources.txt
"$JDK/bin/javac.exe" -nowarn -encoding UTF-8 -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d out/classes @out/sources.txt
"$JDK/bin/java.exe" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 --lib "$ANDROID_JAR" --min-api 26 --output out/dex $(find out/classes -name '*.class')
cp out/base.apk out/unsigned.apk
(cd out/dex && "$JDK/bin/jar.exe" uf ../unsigned.apk classes.dex)
"$BT/zipalign.exe" -f -p 4 out/unsigned.apk out/aligned.apk
cp ../shim/debug.keystore . 2>/dev/null || true
"$JDK/bin/java.exe" -jar "$BT/lib/apksigner.jar" sign --ks debug.keystore --ks-pass pass:android \
  --key-pass pass:android --min-sdk-version 26 --out out/tvdump.apk out/aligned.apk
"$JDK/bin/java.exe" -jar "$BT/lib/apksigner.jar" verify out/tvdump.apk | head -2
ls -l out/tvdump.apk
