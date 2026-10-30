package com.ccos.tv.homepage;

import android.app.Service;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Process;
import android.os.SystemClock;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * 开机看门狗：酷开的开机流程（开机视频/TV app）会在 BOOT_COMPLETED 之后自己把酷开桌面推到前台，
 * 不走 Home 属性。所以开机后两分钟内，每当发现前台是酷开桌面，就通过
 * content://com.tianci.provider 的 COMMON/gotoHomePage 让 com.tianci.system 回 Home
 * （也就是本包的 LaunchActivity → 当贝桌面）。一旦用户自己打开了别的应用就停止，绝不抢屏。
 */
public class BootWatchService extends Service {

    static final String STOCK_HOME = "com.tianci.movieplatform";
    static final String LAUNCHER = "com.dangbei.tvlauncher";
    private static final String BOOT_TV_APP = "com.skyworth.tv";
    private static final Uri SYSTEM_PROVIDER = Uri.parse("content://com.tianci.provider");
    private static final long POLL_MS = 2000L;
    private static final long WATCH_MS = 120000L;
    private static final long EXIT_DELAY_MS = 500L;

    static boolean running;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private long until;

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            String front = foregroundPackage();
            if (front != null && !front.equals(STOCK_HOME) && !front.equals(LAUNCHER)
                    && !front.equals(getPackageName()) && !front.equals(BOOT_TV_APP)) {
                log("front=" + front + ", user opened an app, stop");
                stopSelf();
                return;
            }
            if (LAUNCHER.equals(front)) {
                log("front=" + front + ", launcher is up, stop");
                stopSelf();
                return;
            }
            if (STOCK_HOME.equals(front)) {
                try {
                    getContentResolver().call(SYSTEM_PROVIDER, "COMMON", "gotoHomePage", null);
                    log("front=" + front + ", asked system to go home");
                } catch (RuntimeException e) {
                    log("front=" + front + ", gotoHomePage failed: " + e);
                }
            } else {
                log("front=" + front);
            }
            if (SystemClock.uptimeMillis() < until) {
                handler.postDelayed(this, POLL_MS);
            } else {
                log("watch over");
                stopSelf();
            }
        }
    };

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        running = true;
        BootReceiver.keepEnabled(this);
        log("start, uptime=" + SystemClock.uptimeMillis());
        handler.removeCallbacks(poll);
        until = SystemClock.uptimeMillis() + WATCH_MS;
        handler.post(poll);
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(poll);
        running = false;
        super.onDestroy();
        exitProcess();
    }

    /** 酷开内存管理会杀掉仍在后台的本包进程，被杀后就会错过下一次开机广播，所以用完立刻退出。 */
    static void exitProcess() {
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!running) Process.killProcess(Process.myPid());
            }
        }, EXIT_DELAY_MS);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    /** 酷开的 ActivityManager 把当前前台包名写在 sky.current.apk 属性里。 */
    private static String foregroundPackage() {
        try {
            String pkg = (String) Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class).invoke(null, "sky.current.apk");
            return pkg == null || pkg.isEmpty() ? null : pkg;
        } catch (ReflectiveOperationException | RuntimeException e) {
            return null;
        }
    }

    private void log(String line) {
        File dir = getExternalFilesDir(null);
        if (dir == null) return;
        String time = new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date());
        FileWriter w = null;
        try {
            w = new FileWriter(new File(dir, "watch.log"), true);
            w.write(time + " " + line + "\n");
        } catch (IOException ignored) {
        } finally {
            if (w != null) try { w.close(); } catch (IOException ignored) { }
        }
    }
}
