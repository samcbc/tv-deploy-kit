package com.ccos.tv.homepage;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.os.Bundle;

/** 酷开桌面 shim：开机时 com.tianci.system 会把 Home 指向本包的 LaunchActivity，
 *  这里再拉起当贝桌面。当贝被卸载/停用时回落到酷开自带桌面。 */
public class LaunchActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        BootReceiver.keepEnabled(this);
        // 优先 CleanYourTV 桌面（com.gathin.tvhome），失败回落当贝，再失败回落酷开原生桌面
        if (!start("com.gathin.tvhome", "com.gathin.tvhome.MainActivity")) {
            if (!start("com.dangbei.tvlauncher", "com.dangbei.launcher.ui.main.MainActivity")) {
                start("com.tianci.movieplatform", "com.coocaa.homepage.vast.HomePageActivity");
            }
        }
        finish();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        BootWatchService.exitProcess();
    }

    private boolean start(String pkg, String cls) {
        try {
            startActivity(new Intent(Intent.ACTION_MAIN)
                    .setClassName(pkg, cls)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED));
            return true;
        } catch (ActivityNotFoundException | SecurityException e) {
            return false;
        }
    }
}
