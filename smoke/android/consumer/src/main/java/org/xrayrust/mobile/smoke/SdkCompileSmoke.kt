package org.xrayrust.mobile.smoke

import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayTunRuntimeProfile
import org.xrayrust.mobile.XrayImportedProfile
import org.xrayrust.mobile.XrayProfileFormat
import org.xrayrust.mobile.XrayProfileImporter
import org.xrayrust.mobile.supportsProfileImport
import org.xrayrust.mobile.XrayHysteriaStreamLimits
import org.xrayrust.mobile.XrayTunAdmissionOptions
import org.xrayrust.mobile.XrayTunFlowAdmission
import org.xrayrust.mobile.XrayOutboundProbeResult

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

    fun createWithHostPolicy(config: String): XrayCore = XrayCore.create(
        config,
        hysteriaStreamLimits = XrayHysteriaStreamLimits(128, 64),
        tunAdmission = XrayTunAdmissionOptions(XrayTunFlowAdmission { flow ->
            flow.protocol == 6 || flow.protocol == 17
        }),
    )

    fun rebindCarriers(): Pair<Long, Long> = core.rebindHysteria() to core.rebindWireGuard()

    fun probe(url: String): XrayOutboundProbeResult = core.probeOutboundUrl(url)

    fun stop() {
        core.stop()
        core.close()
    }
}
