package org.xrayrust.mobile.smoke

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayCoreException
import org.xrayrust.mobile.XrayProfileFormat
import org.xrayrust.mobile.XrayProfileImporter

class SdkTransportOptionsNativeTest {
    @Test fun salamanderAndHoppingSurvivePublicImportAndLoad() {
        assumeTrue(java.lang.Boolean.getBoolean("xray.test.nativeImport"))
        val profile = XrayProfileImporter.profile(
            "hy2://synthetic@example.test:443?obfs=salamander&obfs-password=synthetic-test&mport=443,8443-8444",
            XrayProfileFormat.Hysteria2,
        )
        val mask = JSONObject(profile.configJson).getJSONArray("outbounds").getJSONObject(0)
            .getJSONObject("streamSettings").getJSONObject("finalmask")
        assertEquals("salamander", mask.getJSONArray("udp").getJSONObject(0).getString("type"))
        assertTrue(mask.getJSONObject("quicParams").has("udpHop"))
        XrayCore.create(profile.configJson).use { }
    }

    @Test fun fragmentConfigurationReachesNativeValidation() {
        assumeTrue(java.lang.Boolean.getBoolean("xray.test.nativeImport"))
        val config = """
            {"inbounds":[{"protocol":"tun"}],"outbounds":[{"protocol":"trojan",
              "settings":{"address":"127.0.0.1","port":443,"password":"synthetic-test"},
              "streamSettings":{"network":"raw","security":"tls","tlsSettings":{"serverName":"example.test"},
                "finalmask":{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","length":37,"delay":0}}]}}}]}
        """.trimIndent()
        XrayCore.create(config).use { }
        assertThrows(XrayCoreException::class.java) {
            XrayCore.create(config.replace("\"length\":37", "\"length\":0")).close()
        }
    }
}
