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
        val masks = mask.getJSONArray("udp")
        assertEquals("udphop", masks.getJSONObject(0).getString("type"))
        assertEquals("salamander", masks.getJSONObject(1).getString("type"))
        val hop = masks.getJSONObject(0).getJSONObject("settings")
        assertEquals("intervalLocal,intervalRemote", hop.getString("mode"))
        assertEquals("443,8443-8444", hop.getString("remotePorts"))
        assertTrue(mask.getJSONObject("quicParams").getBoolean("disableChromeParrot"))
        XrayCore.create(profile.configJson).use { }
    }

    @Test fun udpNoiseReachesBothQuicCarriersThroughNativeLoad() {
        assumeTrue(java.lang.Boolean.getBoolean("xray.test.nativeImport"))
        val carriers = listOf(
            """{"protocol":"hysteria","settings":{"version":2,"address":"127.0.0.1","port":443},
                "streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"serverName":"example.test"},
                "hysteriaSettings":{"version":2,"auth":"synthetic"},"finalmask":{"udp":[
                {"type":"noise","settings":{"noise":[{"rand":"16-24","delay":1}]}},
                {"type":"salamander","settings":{"password":"synthetic"}}]}}}""",
            """{"protocol":"trojan","settings":{"address":"127.0.0.1","port":443,"password":"synthetic"},
                "streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"serverName":"example.test","alpn":["h3"]},
                "finalmask":{"udp":[{"type":"noise","settings":{"noise":[{"rand":"16-24","delay":1}]}}]}}}""",
        )
        for (outbound in carriers) {
            val config = """{"inbounds":[{"protocol":"tun"}],"outbounds":[$outbound]}"""
            XrayCore.create(config).use { }
            assertThrows(XrayCoreException::class.java) {
                XrayCore.create(config.replace("\"rand\":\"16-24\"", "\"rand\":4097")).close()
            }
        }
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

    @Test fun newDialerProxyAndWireGuardDnsReachNativeValidation() {
        assumeTrue(java.lang.Boolean.getBoolean("xray.test.nativeImport"))
        val chain = """{"outbounds":[{"tag":"entry","protocol":"http","settings":{"address":"192.0.2.10","port":8080},"streamSettings":{"sockopt":{"dialerProxy":"exit"}}},{"tag":"exit","protocol":"freedom"}]}"""
        XrayCore.create(chain).use { }
        assertThrows(XrayCoreException::class.java) {
            XrayCore.create(chain.replace("\"dialerProxy\":\"exit\"", "\"dialerProxy\":\"missing\"")).close()
        }
        val wireguard = """{"outbounds":[{"protocol":"wireguard","settings":{"secretKey":"4242424242424242424242424242424242424242424242424242424242424242","address":["10.44.0.2"],"remoteDNS":["192.0.2.53"],"peers":[{"publicKey":"6363636363636363636363636363636363636363636363636363636363636363","endpoint":"192.0.2.1:51820"}]}}]}"""
        XrayCore.create(wireguard).use { }
        assertThrows(XrayCoreException::class.java) {
            XrayCore.create(wireguard.replace("192.0.2.53", "dns.example")).close()
        }
    }
}
