package org.xrayrust.mobile.smoke

import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayTunRuntimeProfile

class SdkCompileSmoke(private val core: XrayCore) {
    fun selectedProfile(): XrayTunRuntimeProfile = XrayTunRuntimeProfile.Mobile

    fun selectedDnsMode(): XrayDnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly

    fun stop() {
        core.stop()
        core.close()
    }
}

