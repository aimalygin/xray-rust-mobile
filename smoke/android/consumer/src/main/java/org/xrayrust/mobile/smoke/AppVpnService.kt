package org.xrayrust.mobile.smoke

import org.xrayrust.mobile.XrayVpnService
import org.xrayrust.mobile.XrayAndroidUidAdmission
import org.xrayrust.mobile.XrayTunAdmissionOptions
import android.net.ConnectivityManager
import android.os.Build

class AppVpnService : XrayVpnService() {
    override fun tunAdmissionOptions(): XrayTunAdmissionOptions? {
        if (Build.VERSION.SDK_INT < 29) return null
        return XrayTunAdmissionOptions(XrayAndroidUidAdmission(
            getSystemService(ConnectivityManager::class.java), setOf(applicationInfo.uid),
        ))
    }
}
