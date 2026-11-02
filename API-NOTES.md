# Unleashed AJAX API notes (verified against 200.15.6.212 on 2026-11-02)

Transport: see README. Requests are `<ajax-request action=… comp=… updater=…>…</ajax-request>` POSTed to
`/admin/_cmdstat.jsp` (getstat/docmd) or `/admin/_conf.jsp` (getconf/setconf/addobj/updobj/delobj).
JS camelCase keys become kebab-case attributes (`clientType` → `client-type`); keys prefixed `$$` keep their spelling.
Root-level `checkAbility` therefore arrives as `check-ability`. Booleans serialize as `true`/`false`.

## Reads
| Purpose | Request body | Response |
|---|---|---|
| Dashboard stats | getstat stamgr `<wlan LEVEL='1' PERIOD='3600'/><ap LEVEL='1' PERIOD='3600'/><apsummary/>` | `apstamgr-stat` → `wlan` (id, ssid, assoc-stas, state, history rx-bytes/tx-bytes), `ap` (lite + radios + history per band), `apsummary` (connected-num, max-aps, max-clients, 60 s history) |
| Clients | getstat stamgr `<client LEVEL='2' client-type='3'/>` | `client` attrs incl. received-signal-strength, noise-floor, total-rx/tx-bytes/pkts, vap-mac (standalone only; combined request drops dBm) |
| AP details | getstat stamgr `<ap LEVEL='2'/>` (optionally `mac='…'`) | uptime, mem_avail/mem_total, cpu_util, lan_stats_*, sta_*_byte, counters, `if` children |
| AP config | getconf ap-list DECRYPT_X='false' | `ap` (devname, description, location, model, serial, version, ip, group-id, radio children) |
| WLAN config | getconf wlansvc-list DECRYPT_X='false' | `wlansvc` (name, ssid, usage, is-guest, authentication, encryption, vlan-id, enable-type, close-system, wifi6, wpa child) |
| System info | getstat system `<sysinfo/><identity/><mgmt-ip/><time/><unleashed-network/><mesh-policy/><admin/>` | `response/sysinfo` (uptime, version, serial, model, mem_free, cpu_busy), identity name, mgmt-ip, time, admin (username, privilege, idletimeout, lang) |
| Totals | getstat stamgr `<system LEVEL='1'/>` | num-ap, num-sta, num-rogue, *-bytes(-d/-h), `eth` ports |
| Internet | docmd system xcmd='get-connect-status' `<xcmd cmd='get-connect-status'/>` | `xmsg connected ip gateway dns1` |
| Events/alarms | getstat eventd shard-request='true' `<xevent ap='*' sortBy='time' sortDirection='-1'/><pieceStat start='0' number='N' pid='1' requestId='UPDATER'/>` (alarm likewise) | `response/response/xevent|alarm` (msg, severity 1=High 2=Medium 3=Low, time, c, ap, ap-name, lmsg) |
| Neighbours | getstat stamgr `<rogue LEVEL='1'/>` | `rogue` (mac, ssid, radio-band, channel, radio-type, is-open, last-seen) with `detection` (ap, sys-name, rssi) |
| Mesh | getstat stamgr `<meshview/>` | root-ap … |
| Upgrade state | docmd system xcmd='unleashed_query_upgrade_state' | upgrade-ap-list |

## System config elements (getstat/getconf comp='system')
identity(name), mgmt-ip(by-dhcp ip netmask gateway dns1 dns2 …), mgmt-vlan(enabled vlan-id), addif(enabled ip netmask gateway vlan-id),
dhcps(enabled ip-start ip-end range netmask lease dns1 dns2), WAN(mode pppoe-* cellular-*), internal-gateway(enabled ip netmask eth-num wan-port),
dual-wan-gateway, time(by-ntp ntp1 timezone daylight-saving tzString timezone-str time), admin(username privilege idletimeout lang auth-by authsvr-id fallback-local),
log(level num-entries enable-remote-log remote-log-server), remote-mgmt(enabled tcp-ports udp-ports icmp), registration-token, self-heal(enabled auto-ap-power auto-ap-channel auto-ap-channel-5G auto-ap-bandwidth channelfly-2_4G/5G mtbc; auto-channel child),
ap-policy(allow-all authentication prefer-master prefer-second-master master-focus-controller ap-auto-recovery; zd-ip, mgmt-vlan children), credential-reset, dedicated(enabled), mesh-policy(enabled max-hops max-fanout detect-hops hops-warn-threshold detect-fanout fan-out-threshold zt-mesh mesh-radio-id),
snmp(enabled ver ro-community rw-community sys-contact sys-location), snmpv3(enabled; snmpusr rouser/rwuser name auth authPP priv privPP), snmp-trap(enabled ver password ip1-3; trapusr), tr069(tr069enable url url2 informinterval …) [UMM],
background-scan(enabled enabled_5g sleep sleep_5g channel-scan-window …), wips(rogue-reporting malicious-reporting), ips(auto-probe-limit auto-authfail-block auto-authfail-blocktime),
client-load-balancing(radio radio-id=0/1 enabled adjust-threshold weak-bypass strong-bypass …), band-balancing(enabled percent-2_4g), scand(enabled), speedflex, iotg, tunnel(pmtu), tun-cfg(encrypt block-mcast block-bcast), zd-pif,
SR-info, pubnub(enabled) [mobile app remote mgmt], aws-sns(enabled) [mobile notifications], mobile-app-promotion, unleashed-network(unleashed-network-token), dhcpp, mdnsproxyrule-enable-ap, debug-components, debug-log(enabled facility …), upload-debug, icx(allow-all), cluster(enabled peer-ip), email-server, sms-server, guest-access, zero-it(authsvr-id), bypassCNA, adv-radio(country use-dfs-channels only-centrino-channels indoor-channel-allow …)

## Lists (getconf comp='X-list', element X; addobj/updobj/delobj with the same element)
user-list(user), role-list(role: name description can-generate-pass allow-all-wlansvc), authsvr-list(authsvr: type local/guestpass/radius-auth/ad name), acl-list(acl: name description default-mode; deny/accept mac children) [L2 ACL],
policy-list / policy6-list (policy: name default-mode; rule children action type ether-type protocol dst-addr dst-port) [L3 ACL], devicepolicy-list, precedence-list, avppolicy-list / avpapplication-list / avpport-list / arcprofileapp-list [ARC],
urlfilteringpolicy-list, urlfiltering-blockcategories-list(list id name), wificallingpolicy-list(wificallingpolicy name description priority; epdg child), vlanpool-list, mdnsservice-list(mdnsservice name; service type) + bonjour-list [Bonjour Gateway],
ipforward-list, dhcpbind-list, lansvc-list, wlangroup-list, remoteuser-list, mgmtipacl-list, white-list, license-list, alarmdef-list(alarmdef id name msg enabled always-send-mail), zerotouch-list, dpsk-list, hotspot-list, guest-list, lease-list, rogue-block-list, model-list, mesh-list(mesh id name mesh-radio-id), apgroup-list, guestservice-list, modeldef-list

## Writes (mirroring dashboard.js)
- setconf comp='system' with child element(s) carrying `IS_PARTIAL='true'`: e.g. `<identity name='X'/>`, `<admin lang='en_US' IS_PARTIAL='true'/>`, `<log level='1' IS_PARTIAL='true'/>`, `<remote-mgmt enabled tcp-ports udp-ports icmp IS_PARTIAL='true'/>`, `<aws-sns enabled IS_PARTIAL/>`, `<pubnub enabled IS_PARTIAL/>`, `<wips …/>`, `<ips auto-probe-limit auto-authfail-block auto-authfail-blocktime IS_PARTIAL/>`, `<adv-radio country use-dfs-channels only-centrino-channels indoor-channel-allow IS_PARTIAL/>`, `<mesh-policy enabled detect-hops hops-warn-threshold detect-fanout fan-out-threshold zt-mesh mesh-radio-id IS_PARTIAL/>`, `<ap-policy …><zd-ip …/><mgmt-vlan …/></ap-policy>` + `<tunnel pmtu/>`, `<credential-reset …/>`, `<admin username x-password x-oldpassword auth-by authsvr-id fallback-local IS_PARTIAL/>` (password change), `<internal-gateway …/><dual-wan-gateway …/><WAN …/><mgmt-ip by-dhcp [ip netmask gateway dns1 dns2] IS_PARTIAL/><dhcps … IS_PARTIAL/>` (IP settings), `<debug-log … IS_PARTIAL/>`, `<tun-cfg …/><zd-pif …/>`.
- Mesh name/psk: updobj comp='mesh-list' `<mesh id='1' name='…' x-psk='…' mesh-radio-id='1' IS_PARTIAL='true'/>`; mesh uplink/arp: updobj mesh-list `<mesh id='1' IS_PARTIAL='true' mesh-uplink-selection='true|false'/>`.
- WLAN enable: updobj wlansvc-list `<wlansvc id enable-type IS_PARTIAL='true'/>`. AP: updobj ap-list `<ap id IS_PARTIAL='true' mac name devname model description location gps approved group-id …/>`.
- Commands: docmd stamgr xcmd='reset' check-ability='2' `<xcmd cmd='reset' tag='ap' ap=MAC/>`; xcmd='block' check-ability='10' `<xcmd cmd='block' tag='client'><client client=MAC acl-id='1' hostname=…/></xcmd>`; xcmd='delete' check-ability='2' `<xcmd cmd='delete' tag='client' client=MAC/>`; xcmd='rename' `<xcmd cmd='rename' tag='client' client=MAC rename=NAME/>`; xcmd='stamgr' `<xcmd cmd='favourite'|'mark-iot' tag='client' enable='1|0' client=MAC/>`; eventd `<xcmd cmd='del-all-events' checkAbility='6'/>`.
- Unblock: updobj acl-list `<acl id='1' name='System' description='System' default-mode='allow' EDITABLE='false'>remaining deny entries</acl>`.
