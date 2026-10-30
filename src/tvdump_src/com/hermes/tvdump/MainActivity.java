package com.hermes.tvdump;

import android.app.Activity;
import android.content.ContentResolver;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;

/**
 * 通用 execLinuxCmd 试验器：
 * 从 /data/local/tmp/cmd.txt 读取若干行，每行格式  "cmd编号|参数"
 * 依次通过 content://com.tianci.provider 的 COMMON/execLinuxCmd 执行，
 * 结果打到 logcat（tag=TVDump），用 adb logcat -s TVDump 取。
 *
 * LINUX_CMD 枚举：CHMOD=0, CP=1, MKDIR=2, MOUNT=3, MV=4, PING=5,
 *                 PM_INSTALL=6, PM_UNINSTALL=7, REBOOT=8, SYNC=9
 */
public class MainActivity extends Activity {

    private static final String TAG = "TVDump";
    private static final String URI = "content://com.tianci.provider";
    private static final String CMD_FILE = "/data/local/tmp/cmd.txt";
    private final StringBuilder log = new StringBuilder();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        new Thread(new Runnable() { public void run() { runAll(); } }).start();
    }

    private void runAll() {
        Log.i(TAG, "=== start ===");
        BufferedReader br = null;
        try {
            br = new BufferedReader(new FileReader(CMD_FILE));
            String line;
            int n = 0;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.length() == 0 || line.startsWith("#")) continue;
                int bar = line.indexOf('|');
                if (bar <= 0) { Log.i(TAG, "skip: " + line); continue; }
                int cmd;
                try { cmd = Integer.parseInt(line.substring(0, bar).trim()); }
                catch (Exception e) { Log.i(TAG, "bad cmd: " + line); continue; }
                String param = line.substring(bar + 1);
                n++;
                doExec(n, cmd, param);
            }
            Log.i(TAG, "done count=" + n);
        } catch (Throwable t) {
            Log.e(TAG, "read " + CMD_FILE + " fail: " + t, t);
        } finally {
            try { if (br != null) br.close(); } catch (Exception ignored) { }
        }
        Log.i(TAG, "=== DONE ===");
        writeOut();
    }

    private void line(String s) {
        Log.i(TAG, s);
        log.append(s).append('\n');
    }

    private void writeOut() {
        try {
            File dir = getExternalFilesDir(null);
            if (dir != null) {
                File f = new File(dir, "tvdump.log");
                FileWriter w = new FileWriter(f, false);
                w.write(log.toString());
                w.close();
                Log.i(TAG, "written: " + f.getAbsolutePath());
            }
        } catch (Throwable e) {
            Log.e(TAG, "write fail", e);
        }
    }

    private void doExec(int idx, int cmd, String param) {
        // provider 端是 bundle.getParcelable("param") → param 必须是 Parcelable 的 Bundle
        for (int variant = 0; variant < 2; variant++) {
            try {
                Bundle inner = new Bundle();
                inner.putInt("cmd", cmd);
                inner.putString("param", param);
                Bundle extras = new Bundle();
                extras.putBoolean("method_set", variant == 1);
                extras.putParcelable("param", inner);
                ContentResolver cr = getContentResolver();
                Bundle ret = cr.call(Uri.parse(URI), "COMMON", "execLinuxCmd", extras);
                line("#" + idx + " v" + variant + " cmd=" + cmd + " param=[" + param + "] ret="
                        + (ret == null ? "null" : ret.toString()));
            } catch (Throwable t) {
                line("#" + idx + " v" + variant + " EX " + t.getClass().getSimpleName() + ": " + t.getMessage());
            }
        }
    }
}
