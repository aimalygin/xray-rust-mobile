package org.xrayrust.mobile.smoke

import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayTunRuntimeProfile
import org.xrayrust.mobile.XrayImportedProfile
import org.xrayrust.mobile.XrayProfileFormat
import org.xrayrust.mobile.XrayProfileImporter
import org.xrayrust.mobile.supportsProfileImport

class SdkCompileSmoke(private val core: XrayCore) {
    fun selectedProfile(): XrayTunRuntimeProfile = XrayTunRuntimeProfile.Mobile

    fun selectedDnsMode(): XrayDnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly

    fun supportedClientFormats(): List<XrayProfileFormat> {
        val info = XrayCore.ffiInfo()
        return listOf(XrayProfileFormat.Trojan, XrayProfileFormat.Shadowsocks2022,
            XrayProfileFormat.Vmess).filter(info::supportsProfileImport)
    }

    fun importClient(text: String, format: XrayProfileFormat): XrayImportedProfile =
        XrayProfileImporter.profile(text, format)

    fun stop() {
        core.stop()
        core.close()
    }
}
