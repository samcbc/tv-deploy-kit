package com.ccos.tv.homepage;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

/** 开机广播：酷开会把第三方开机广播接收器禁用掉，这里每次运行都把自己重新启用，
 *  然后启动开机看门狗服务。 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        keepEnabled(context);
        context.startService(new Intent(context, BootWatchService.class));
    }

    /** 把本接收器重新置为启用状态：酷开在某些情况下会把它禁用，禁用后就再也收不到开机广播。 */
    static void keepEnabled(Context context) {
        try {
            ComponentName self = new ComponentName(context, BootReceiver.class);
            PackageManager pm = context.getPackageManager();
            if (pm.getComponentEnabledSetting(self) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                pm.setComponentEnabledSetting(self,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP);
            }
        } catch (RuntimeException ignored) {
        }
    }
}
