import Foundation

enum SettingsGroup: String, CaseIterable, Identifiable, Hashable {
    case system, administration, services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .administration: return "Administration"
        case .services: return "Services"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "gearshape"
        case .administration: return "person.badge.key"
        case .services: return "square.stack.3d.up"
        }
    }

    var pages: [SettingsPage] {
        switch self {
        case .system: return SettingsCatalog.system
        case .administration: return SettingsCatalog.administration
        case .services: return SettingsCatalog.services
        }
    }
}

struct SettingsPage: Identifiable {
    enum CustomKind {
        case preferences, backupRestore, upgrade, diagnostics, certificate, technicalSupport
    }

    enum Content {
        case config(ConfigPageSpec)
        case list(ListPageSpec)
        case composite(config: ConfigPageSpec?, lists: [ListPageSpec])
        case custom(CustomKind)
    }

    var id: String
    var title: String
    var systemImage: String
    var content: Content
}

private func f(_ path: String, _ key: String, _ label: String, _ kind: ConfigFieldKind = .text,
               help: String? = nil, visibleWhen: (@Sendable (ConfigValues) -> Bool)? = nil) -> ConfigField {
    ConfigField(path, key, label, kind, help: help, visibleWhen: visibleWhen)
}
private typealias O = ConfigOptions

enum SettingsCatalog {
    /// Every declarative config page across the three groups (used by the headless `--set` mode).
    static var allConfigPages: [ConfigPageSpec] {
        (system + administration + services).compactMap { page in
            switch page.content {
            case .config(let spec): return spec
            case .composite(let spec, _): return spec
            default: return nil
            }
        } + [preferences]
    }

    // MARK: System

    static let systemInfo = ConfigPageSpec(
        id: "system-info", title: "System Info", subtitle: "Name, identity and preferred master", systemImage: "info.circle",
        readElements: ["identity", "sysinfo", "unleashed-network", "ap-policy"],
        sections: [
            ConfigSection("Identity", [
                f("identity", "name", "System name", .text, help: "Shown in the web UI header and in mobile apps.", visibleWhen: nil),
                f("sysinfo", "version", "Firmware", .readOnly, help: nil, visibleWhen: nil),
                f("sysinfo", "display-model", "Master AP model", .readOnly, help: nil, visibleWhen: nil),
                f("sysinfo", "serial", "Serial number", .readOnly, help: nil, visibleWhen: nil),
                f("unleashed-network", "unleashed-network-token", "Unleashed ID", .readOnly, help: "Used to register the network with Ruckus cloud services.", visibleWhen: nil),
            ]),
            ConfigSection("Preferred master", footer: "Changing the preferred master reboots the current master AP and briefly interrupts the network.", [
                f("ap-policy", "prefer-master", "Primary preferred master", .dynamicPicker(O.accessPoints), help: nil, visibleWhen: nil),
                f("ap-policy", "prefer-second-master", "Secondary preferred master", .dynamicPicker(O.accessPoints), help: nil, visibleWhen: nil),
                f("ap-policy", "master-focus-controller", "Disable WLAN service on master AP", O.trueFalse, help: "Only takes effect with three or more connected APs.", visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("identity", partial: false), ConfigWrite("unleashed-network"), ConfigWrite("ap-policy")],
        applyWarning: nil
    )

    static let ipSettings = ConfigPageSpec(
        id: "ip-settings", title: "IP Settings", subtitle: "Management address, DHCP server and management VLAN", systemImage: "network",
        readElements: ["mgmt-ip", "internal-gateway", "WAN", "dhcps", "mgmt-vlan"],
        sections: [
            ConfigSection("Gateway mode", [
                f("internal-gateway", "enabled", "Gateway mode enabled", .readOnly, help: "When the master AP acts as the internet gateway. Change this from the web UI wizard.", visibleWhen: nil),
                f("internal-gateway", "ip", "LAN address", .readOnly, help: nil, visibleWhen: nil),
                f("internal-gateway", "netmask", "LAN netmask", .readOnly, help: nil, visibleWhen: nil),
                f("WAN", "mode", "WAN mode", .readOnly, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Management IP", footer: "Applies to the master AP's management interface (the WAN port in gateway mode).", [
                f("mgmt-ip", "by-dhcp", "Obtain address automatically (DHCP)", O.trueFalse, help: nil, visibleWhen: nil),
                f("mgmt-ip", "ip", "IP address", .text, help: nil, visibleWhen: { !$0.bool("mgmt-ip", "by-dhcp") }),
                f("mgmt-ip", "netmask", "Netmask", .text, help: nil, visibleWhen: { !$0.bool("mgmt-ip", "by-dhcp") }),
                f("mgmt-ip", "gateway", "Gateway", .text, help: nil, visibleWhen: { !$0.bool("mgmt-ip", "by-dhcp") }),
                f("mgmt-ip", "dns1", "Primary DNS", .text, help: nil, visibleWhen: { !$0.bool("mgmt-ip", "by-dhcp") }),
                f("mgmt-ip", "dns2", "Secondary DNS", .text, help: nil, visibleWhen: { !$0.bool("mgmt-ip", "by-dhcp") }),
            ]),
            ConfigSection("DHCP server", [
                f("dhcps", "enabled", "Run DHCP server", O.trueFalse, help: nil, visibleWhen: nil),
                f("dhcps", "ip-start", "Range start", .text, help: nil, visibleWhen: { $0.bool("dhcps", "enabled") }),
                f("dhcps", "ip-end", "Range end", .text, help: nil, visibleWhen: { $0.bool("dhcps", "enabled") }),
                f("dhcps", "netmask", "Netmask", .text, help: nil, visibleWhen: { $0.bool("dhcps", "enabled") }),
                f("dhcps", "lease", "Lease time", .text, help: "For example 12h or 1d.", visibleWhen: { $0.bool("dhcps", "enabled") }),
                f("dhcps", "dns1", "Primary DNS", .text, help: nil, visibleWhen: { $0.bool("dhcps", "enabled") }),
                f("dhcps", "dns2", "Secondary DNS", .text, help: nil, visibleWhen: { $0.bool("dhcps", "enabled") }),
            ]),
            ConfigSection("Management VLAN", [
                f("mgmt-vlan", "enabled", "Tag management traffic", O.trueFalse, help: nil, visibleWhen: nil),
                f("mgmt-vlan", "vlan-id", "VLAN ID", .text, help: nil, visibleWhen: { $0.bool("mgmt-vlan", "enabled") }),
            ]),
        ],
        writes: [ConfigWrite("mgmt-ip"), ConfigWrite("dhcps"), ConfigWrite("mgmt-vlan")],
        applyWarning: "Changing addressing can make the controller unreachable from this Mac. Make sure you can still reach the new address before applying."
    )

    static let systemTime = ConfigPageSpec(
        id: "system-time", title: "System Time", subtitle: "NTP and time zone", systemImage: "clock",
        readElements: ["time"],
        sections: [
            ConfigSection("Clock", [
                f("time", "time", "Controller time", .readOnlyDate, help: nil, visibleWhen: nil),
                f("time", "by-ntp", "Synchronise with NTP", O.trueFalse, help: nil, visibleWhen: nil),
                f("time", "ntp1", "NTP server", .text, help: nil, visibleWhen: { $0.bool("time", "by-ntp") }),
                f("time", "timezone", "Time zone", .dynamicPicker(O.timezones), help: nil, visibleWhen: nil),
                f("time", "daylight-saving", "Daylight saving time", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("time")],
        applyWarning: nil
    )

    static let countryCode = ConfigPageSpec(
        id: "country-code", title: "Country Code", subtitle: "Regulatory domain and channel options", systemImage: "globe",
        readElements: ["adv-radio", "sysinfo"],
        sections: [
            ConfigSection("Regulatory", footer: "Changing the country code reboots every access point.", [
                f("adv-radio", "country", "Country", .picker(O.countries), help: nil, visibleWhen: nil),
                f("adv-radio", "use-dfs-channels", "Allow DFS channels", O.oneZero, help: "Radar-detection channels on 5 GHz.", visibleWhen: nil),
                f("adv-radio", "only-centrino-channels", "Prefer channels supported by legacy Intel clients", O.oneZero, help: nil, visibleWhen: nil),
                f("adv-radio", "indoor-channel-allow", "Allow indoor-only channels on outdoor APs", O.oneZero, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("adv-radio")],
        applyWarning: "All access points will reboot to apply the new regulatory settings."
    )

    static let roles = ListPageSpec(
        id: "roles", title: "Roles", subtitle: "Groups of users with WLAN permissions", systemImage: "person.2",
        component: "role-list", element: "role",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("description", "Description"), ListColumn("allow-all-wlansvc", "All WLANs", width: 80), ListColumn("can-generate-pass", "Guest pass", width: 80)],
        fields: [
            f("role", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("role", "description", "Description", .text, help: nil, visibleWhen: nil),
            f("role", "allow-all-wlansvc", "Allow access to all WLANs", O.trueFalse, help: nil, visibleWhen: nil),
            f("role", "can-generate-pass", "Can generate guest passes", O.trueFalse, help: nil, visibleWhen: nil),
        ],
        note: nil
    )

    static let users = ListPageSpec(
        id: "users", title: "Users", subtitle: "Local user accounts (internal database)", systemImage: "person.crop.circle",
        component: "user-list", element: "user",
        columns: [ListColumn("name", "User name", width: 160), ListColumn("full-name", "Full name"), ListColumn("role-id", "Role", width: 80)],
        fields: [
            f("user", "name", "User name", .text, help: nil, visibleWhen: nil),
            f("user", "full-name", "Full name", .text, help: nil, visibleWhen: nil),
            f("user", "x-password", "Password", .password, help: nil, visibleWhen: nil),
            f("user", "role-id", "Role", .dynamicPicker(O.roles), help: nil, visibleWhen: nil),
        ],
        note: nil
    )

    static let mesh = ConfigPageSpec(
        id: "mesh", title: "Mesh", subtitle: "Wireless backhaul between access points", systemImage: "point.3.connected.trianglepath.dotted",
        readElements: ["mesh-policy"],
        listReads: [ConfigListRead(component: "mesh-list", element: "mesh", alias: "mesh", decrypt: false)],
        sections: [
            ConfigSection("Mesh network", footer: "Mesh changes are pushed to every AP and can reboot mesh nodes.", [
                f("mesh-policy", "enabled", "Enable mesh", O.trueFalse, help: nil, visibleWhen: nil),
                f("mesh", "name", "Mesh name (ESSID)", .text, help: nil, visibleWhen: nil),
                f("mesh", "x-psk", "Mesh passphrase", .password, help: "Leave blank to keep the current passphrase.", visibleWhen: nil),
                f("mesh-policy", "mesh-radio-id", "Mesh radio", .picker([ConfigOption("1", "5 GHz"), ConfigOption("0", "2.4 GHz")]), help: nil, visibleWhen: nil),
                f("mesh-policy", "zt-mesh", "Zero-touch mesh", O.enabledDisabled, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Topology detection", [
                f("mesh-policy", "detect-hops", "Warn on hop count", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("mesh-policy", "hops-warn-threshold", "Hop warning threshold", .number(1...255), help: nil, visibleWhen: { $0["mesh-policy", "detect-hops"] == "enabled" }),
                f("mesh-policy", "detect-fanout", "Warn on fan-out", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("mesh-policy", "fan-out-threshold", "Fan-out warning threshold", .number(1...255), help: nil, visibleWhen: { $0["mesh-policy", "detect-fanout"] == "enabled" }),
            ]),
        ],
        writes: [ConfigWrite("mesh-policy"), ConfigWrite("mesh", kind: .updobj(component: "mesh-list"))],
        applyWarning: "Applying mesh settings can reboot mesh access points and briefly disconnect their clients."
    )

    static let system: [SettingsPage] = [
        SettingsPage(id: systemInfo.id, title: systemInfo.title, systemImage: systemInfo.systemImage, content: .config(systemInfo)),
        SettingsPage(id: ipSettings.id, title: ipSettings.title, systemImage: ipSettings.systemImage, content: .config(ipSettings)),
        SettingsPage(id: systemTime.id, title: systemTime.title, systemImage: systemTime.systemImage, content: .config(systemTime)),
        SettingsPage(id: countryCode.id, title: countryCode.title, systemImage: countryCode.systemImage, content: .config(countryCode)),
        SettingsPage(id: roles.id, title: roles.title, systemImage: roles.systemImage, content: .list(roles)),
        SettingsPage(id: users.id, title: users.title, systemImage: users.systemImage, content: .list(users)),
        SettingsPage(id: mesh.id, title: mesh.title, systemImage: mesh.systemImage, content: .config(mesh)),
    ]

    // MARK: Administration

    static let preferences = ConfigPageSpec(
        id: "preferences", title: "Preferences", subtitle: "Language, session timeout and admin password", systemImage: "slider.horizontal.3",
        readElements: ["admin"],
        sections: [
            ConfigSection("Web interface", [
                f("admin", "lang", "Language", .picker(O.languages), help: nil, visibleWhen: nil),
                f("admin", "idletimeout", "Session idle timeout (minutes)", .number(1...1440), help: nil, visibleWhen: nil),
                f("admin", "auth-by", "Authenticate admins", .readOnly, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("admin")],
        applyWarning: nil
    )

    static let networkManagement = ConfigPageSpec(
        id: "network-management", title: "Network Management", subtitle: "SNMP, syslog and Unleashed Multi-Site Manager", systemImage: "server.rack",
        readElements: ["snmp", "snmpv3", "snmp-trap", "tr069", "log"],
        sections: [
            ConfigSection("SNMPv2 agent", [
                f("snmp", "enabled", "Enable SNMPv2 agent", O.trueFalse, help: nil, visibleWhen: nil),
                f("snmp", "ro-community", "Read-only community", .text, help: nil, visibleWhen: { $0.bool("snmp", "enabled") }),
                f("snmp", "rw-community", "Read-write community", .text, help: nil, visibleWhen: { $0.bool("snmp", "enabled") }),
                f("snmp", "sys-contact", "System contact", .text, help: nil, visibleWhen: { $0.bool("snmp", "enabled") }),
                f("snmp", "sys-location", "System location", .text, help: nil, visibleWhen: { $0.bool("snmp", "enabled") }),
            ]),
            ConfigSection("SNMPv3 agent", [
                f("snmpv3", "enabled", "Enable SNMPv3 agent", O.trueFalse, help: nil, visibleWhen: nil),
                f("snmpv3/snmpusr[role=rouser]", "name", "Read-only user", .text, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rouser]", "auth", "Read-only auth", .picker([ConfigOption("MD5", "MD5"), ConfigOption("SHA", "SHA")]), help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rouser]", "authPP", "Read-only auth passphrase", .password, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rouser]", "priv", "Read-only privacy", .picker([ConfigOption("DES", "DES"), ConfigOption("AES", "AES")]), help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rouser]", "privPP", "Read-only privacy passphrase", .password, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rwuser]", "name", "Read-write user", .text, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rwuser]", "auth", "Read-write auth", .picker([ConfigOption("MD5", "MD5"), ConfigOption("SHA", "SHA")]), help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rwuser]", "authPP", "Read-write auth passphrase", .password, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rwuser]", "priv", "Read-write privacy", .picker([ConfigOption("DES", "DES"), ConfigOption("AES", "AES")]), help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
                f("snmpv3/snmpusr[role=rwuser]", "privPP", "Read-write privacy passphrase", .password, help: nil, visibleWhen: { $0.bool("snmpv3", "enabled") }),
            ]),
            ConfigSection("SNMP traps", [
                f("snmp-trap", "enabled", "Send SNMP traps", O.trueFalse, help: nil, visibleWhen: nil),
                f("snmp-trap", "ver", "Trap version", .picker([ConfigOption("2", "SNMPv2"), ConfigOption("3", "SNMPv3")]), help: nil, visibleWhen: { $0.bool("snmp-trap", "enabled") }),
                f("snmp-trap", "password", "Community", .text, help: nil, visibleWhen: { $0.bool("snmp-trap", "enabled") }),
                f("snmp-trap", "ip1", "Trap server 1", .text, help: nil, visibleWhen: { $0.bool("snmp-trap", "enabled") }),
                f("snmp-trap", "ip2", "Trap server 2", .text, help: nil, visibleWhen: { $0.bool("snmp-trap", "enabled") }),
                f("snmp-trap", "ip3", "Trap server 3", .text, help: nil, visibleWhen: { $0.bool("snmp-trap", "enabled") }),
            ]),
            ConfigSection("Unleashed Multi-Site Manager", [
                f("tr069", "tr069enable", "Managed by UMM", O.trueFalse, help: nil, visibleWhen: nil),
                f("tr069", "url", "UMM server URL", .text, help: nil, visibleWhen: { $0.bool("tr069", "tr069enable") }),
                f("tr069", "informinterval", "Inform interval (minutes)", .number(1...1440), help: nil, visibleWhen: { $0.bool("tr069", "tr069enable") }),
            ]),
            ConfigSection("Syslog", [
                f("log", "level", "Event level to log", .picker([ConfigOption("1", "High"), ConfigOption("2", "Medium and above"), ConfigOption("3", "All")]), help: nil, visibleWhen: nil),
                f("log", "enable-remote-log", "Send to remote syslog server", O.trueFalse, help: nil, visibleWhen: nil),
                f("log", "remote-log-server", "Syslog server", .text, help: nil, visibleWhen: { $0.bool("log", "enable-remote-log") }),
            ]),
        ],
        writes: [ConfigWrite("snmp"), ConfigWrite("snmpv3", constants: ["ver": "3"]), ConfigWrite("snmp-trap"), ConfigWrite("tr069"), ConfigWrite("log")],
        applyWarning: nil
    )

    static let remoteManagement = ConfigPageSpec(
        id: "remote-management", title: "Remote Management", subtitle: "WAN-side access and the Unleashed mobile app", systemImage: "antenna.radiowaves.left.and.right.circle",
        readElements: ["remote-mgmt", "pubnub", "aws-sns"],
        sections: [
            ConfigSection("WAN port services", footer: "Ports reachable on the WAN side of the master AP in gateway mode.", [
                f("remote-mgmt", "tcp-ports", "Allowed TCP ports", .text, help: "Comma separated, for example 443,80.", visibleWhen: nil),
                f("remote-mgmt", "udp-ports", "Allowed UDP ports", .text, help: nil, visibleWhen: nil),
                f("remote-mgmt", "icmp", "Respond to ping", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Mobile app", [
                f("pubnub", "enabled", "Remote management via Ruckus cloud", O.trueFalse, help: nil, visibleWhen: nil),
                f("aws-sns", "enabled", "Push notifications", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("remote-mgmt"), ConfigWrite("pubnub"), ConfigWrite("aws-sns")],
        applyWarning: nil
    )

    static let administration: [SettingsPage] = [
        SettingsPage(id: "preferences", title: "Preferences", systemImage: "slider.horizontal.3", content: .custom(.preferences)),
        SettingsPage(id: "backup-restore", title: "Backup & Restore", systemImage: "externaldrive.badge.timemachine", content: .custom(.backupRestore)),
        SettingsPage(id: "upgrade", title: "Upgrade", systemImage: "arrow.up.circle", content: .custom(.upgrade)),
        SettingsPage(id: "diagnostics", title: "Diagnostics", systemImage: "stethoscope", content: .custom(.diagnostics)),
        SettingsPage(id: "certificate", title: "Certificate", systemImage: "lock.shield", content: .custom(.certificate)),
        SettingsPage(id: networkManagement.id, title: networkManagement.title, systemImage: networkManagement.systemImage, content: .config(networkManagement)),
        SettingsPage(id: remoteManagement.id, title: remoteManagement.title, systemImage: remoteManagement.systemImage, content: .config(remoteManagement)),
        SettingsPage(id: "technical-support", title: "Technical Support", systemImage: "lifepreserver", content: .custom(.technicalSupport)),
    ]

    // MARK: Services

    static let aaaServers = ListPageSpec(
        id: "aaa", title: "AAA Servers", subtitle: "RADIUS, Active Directory and LDAP servers", systemImage: "key.horizontal",
        component: "authsvr-list", element: "authsvr", decrypt: true,
        columns: [ListColumn("name", "Name", width: 180), ListColumn("type", "Type", width: 110), ListColumn("primary-server", "Server"), ListColumn("primary-port", "Port", width: 60)],
        fields: [
            f("authsvr", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("authsvr", "type", "Type", .picker([ConfigOption("radius-auth", "RADIUS"), ConfigOption("radius-acct", "RADIUS accounting"), ConfigOption("ad", "Active Directory"), ConfigOption("ldap", "LDAP")]), help: nil, visibleWhen: nil),
            f("authsvr", "primary-server", "Server address", .text, help: nil, visibleWhen: nil),
            f("authsvr", "primary-port", "Port", .text, help: "1812 for RADIUS authentication, 1813 for accounting, 389 for AD/LDAP.", visibleWhen: nil),
            f("authsvr", "x-primary-secret", "Shared secret", .password, help: nil, visibleWhen: { $0["authsvr", "type"].hasPrefix("radius") }),
            f("authsvr", "ad-domain", "Windows domain", .text, help: nil, visibleWhen: { $0["authsvr", "type"] == "ad" }),
            f("authsvr", "ldap-base-dn", "Base DN", .text, help: nil, visibleWhen: { $0["authsvr", "type"] == "ldap" }),
        ],
        note: "Attribute names for new servers follow the ZoneDirector schema; verify the first server you add in the web UI."
    )

    static let l2ACLs = ListPageSpec(
        id: "acl", title: "Layer 2 Access Control", subtitle: "MAC address allow/deny lists", systemImage: "list.bullet.rectangle",
        component: "acl-list", element: "acl",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("description", "Description"), ListColumn("default-mode", "Default", width: 80)],
        fields: [
            f("acl", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("acl", "description", "Description", .text, help: nil, visibleWhen: nil),
            f("acl", "default-mode", "Default action", .picker([ConfigOption("allow", "Allow all except listed"), ConfigOption("deny", "Deny all except listed")]), help: nil, visibleWhen: nil),
        ],
        note: "MAC entries inside an ACL are shown in the row details; the System ACL holds clients blocked from the Clients page."
    )

    static let l3ACLs = ListPageSpec(
        id: "policy", title: "Layer 3/4 Access Control", subtitle: "IP and port rules applied to WLANs", systemImage: "list.bullet.indent",
        component: "policy-list", element: "policy",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("description", "Description"), ListColumn("default-mode", "Default", width: 80)],
        fields: [
            f("policy", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("policy", "description", "Description", .text, help: nil, visibleWhen: nil),
            f("policy", "default-mode", "Default action", .picker([ConfigOption("allow", "Allow"), ConfigOption("deny", "Deny")]), help: nil, visibleWhen: nil),
        ],
        canAdd: false,
        note: "Rules are listed in the row details. Rule editing is not supported in this version; use the web UI."
    )

    static let devicePolicies = ListPageSpec(
        id: "devicepolicy", title: "Device Policies", subtitle: "Per-device-type access rules", systemImage: "iphone.gen3",
        component: "devicepolicy-list", element: "devicepolicy",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("description", "Description"), ListColumn("default-mode", "Default", width: 80)],
        fields: [
            f("devicepolicy", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("devicepolicy", "description", "Description", .text, help: nil, visibleWhen: nil),
            f("devicepolicy", "default-mode", "Default action", .picker([ConfigOption("allow", "Allow"), ConfigOption("deny", "Deny")]), help: nil, visibleWhen: nil),
        ],
        canAdd: false, note: nil
    )

    static let arcPolicies = ListPageSpec(
        id: "arc", title: "Application Recognition & Control", subtitle: "Application policies and user-defined applications", systemImage: "app.badge.checkmark",
        component: "avppolicy-list", element: "avppolicy",
        columns: [ListColumn("name", "Name", width: 180), ListColumn("description", "Description")],
        fields: [
            f("avppolicy", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("avppolicy", "description", "Description", .text, help: nil, visibleWhen: nil),
        ],
        canAdd: false, note: "Policy rules are shown in the row details; create policies in the web UI."
    )

    static let bonjourGateway = ConfigPageSpec(
        id: "bonjour", title: "Bonjour Gateway", subtitle: "Forward mDNS services between VLANs", systemImage: "airplayaudio",
        readElements: ["mdnsproxyrule-enable-ap"],
        sections: [ConfigSection("Bonjour gateway", [
            f("mdnsproxyrule-enable-ap", "enabled", "Enable Bonjour gateway on access points", O.trueFalse, help: nil, visibleWhen: nil),
        ])],
        writes: [ConfigWrite("mdnsproxyrule-enable-ap")],
        applyWarning: nil
    )

    static let bonjourRules = ListPageSpec(
        id: "bonjour-rules", title: "Bonjour rules", subtitle: "Service forwarding rules", systemImage: "arrow.left.arrow.right",
        component: "bonjour-list", element: "bonjour",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("mdnsservice-id", "Service", width: 80), ListColumn("from-vlan", "From VLAN", width: 90), ListColumn("to-vlan", "To VLAN", width: 90), ListColumn("notes", "Notes")],
        fields: [
            f("bonjour", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("bonjour", "mdnsservice-id", "Service ID", .text, help: "From the mDNS service list (1 = AirDisk, 2 = AirPlay, 4 = AirPrint, 8 = Apple TV …).", visibleWhen: nil),
            f("bonjour", "from-vlan", "From VLAN", .text, help: nil, visibleWhen: nil),
            f("bonjour", "to-vlan", "To VLAN", .text, help: nil, visibleWhen: nil),
            f("bonjour", "notes", "Notes", .text, help: nil, visibleWhen: nil),
        ],
        note: nil
    )

    static let dpsk = ListPageSpec(
        id: "dpsk", title: "Dynamic PSK", subtitle: "Per-device pre-shared keys", systemImage: "key",
        component: "stamgr", element: "dpsk", readAction: .getstat, statBody: "<dpsk-list/>",
        columns: [ListColumn("user", "User", width: 160), ListColumn("mac", "MAC", width: 150), ListColumn("wlan", "WLAN", width: 140), ListColumn("expire", "Expires"), ListColumn("vlan", "VLAN", width: 60)],
        fields: [f("dpsk", "user", "User", .text, help: nil, visibleWhen: nil)],
        canAdd: false, canEdit: false,
        note: "Generate new DPSKs from the WLAN's Dynamic PSK settings in the web UI; keys created there appear here."
    )

    static let guestAccess = ConfigPageSpec(
        id: "guest-access", title: "Guest Access Service", subtitle: "Guest pass behaviour and portal", systemImage: "person.badge.key",
        readElements: ["guest-access"], readAction: .getconf,
        sections: [
            ConfigSection("Guest passes", [
                f("guest-access", "auth-by", "Authenticate guests by", .picker([ConfigOption("guestpass", "Guest pass"), ConfigOption("none", "No authentication")]), help: nil, visibleWhen: nil),
                f("guest-access", "valid", "Guest pass validity (days)", .number(1...365), help: nil, visibleWhen: nil),
                f("guest-access", "countdown-by-issued", "Count validity from issue time", O.trueFalse, help: "Otherwise from first use.", visibleWhen: nil),
                f("guest-access", "self-service", "Allow self-service registration", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Portal", [
                f("guest-access", "title", "Welcome title", .text, help: nil, visibleWhen: nil),
                f("guest-access", "show-tou", "Show terms of use", O.trueFalse, help: nil, visibleWhen: nil),
                f("guest-access", "tou", "Terms of use", .multiline, help: nil, visibleWhen: { $0.bool("guest-access", "show-tou") }),
                f("guest-access", "redirect", "After login", .picker([ConfigOption("orig", "Original destination"), ConfigOption("url", "Fixed URL")]), help: nil, visibleWhen: nil),
                f("guest-access", "redirect-url", "Redirect URL", .text, help: nil, visibleWhen: { $0["guest-access", "redirect"] == "url" }),
            ]),
        ],
        writes: [ConfigWrite("guest-access")],
        applyWarning: nil
    )

    static let guestServices = ListPageSpec(
        id: "guestservice", title: "Guest services", subtitle: "Portal profiles assigned to guest WLANs", systemImage: "rectangle.3.group",
        component: "guestservice-list", element: "guestservice",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("auth-by", "Auth", width: 90), ListColumn("valid", "Valid days", width: 80), ListColumn("title", "Portal title")],
        fields: [
            f("guestservice", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("guestservice", "title", "Portal title", .text, help: nil, visibleWhen: nil),
            f("guestservice", "valid", "Guest pass validity (days)", .number(1...365), help: nil, visibleWhen: nil),
            f("guestservice", "show-tou", "Show terms of use", O.trueFalse, help: nil, visibleWhen: nil),
            f("guestservice", "self-service", "Self-service registration", O.trueFalse, help: nil, visibleWhen: nil),
        ],
        canAdd: false, canDelete: false, note: nil
    )

    static let hotspots = ListPageSpec(
        id: "hotspot", title: "Hotspot Services", subtitle: "WISPr captive portal profiles", systemImage: "wifi.square",
        component: "hotspot-list", element: "hotspot",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("login-page", "Login page"), ListColumn("start-page", "Start page")],
        fields: [
            f("hotspot", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("hotspot", "login-page", "Login page URL", .text, help: nil, visibleWhen: nil),
            f("hotspot", "start-page", "Start page URL", .text, help: nil, visibleWhen: nil),
            f("hotspot", "idle-timeout", "Idle timeout (minutes)", .text, help: nil, visibleWhen: nil),
            f("hotspot", "session-timeout", "Session timeout (minutes)", .text, help: nil, visibleWhen: nil),
        ],
        note: "Attribute names follow the ZoneDirector schema; verify the first profile you add in the web UI."
    )

    static let radioControl = ConfigPageSpec(
        id: "radio-control", title: "Radio Control", subtitle: "Self healing, scanning and balancing", systemImage: "dot.radiowaves.left.and.right",
        readElements: ["self-heal", "background-scan", "client-load-balancing", "band-balancing", "scand"],
        sections: [
            ConfigSection("Self healing", [
                f("self-heal", "auto-ap-channel", "Automatically adjust 2.4 GHz channels", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("self-heal", "channelfly-2_4G", "Use ChannelFly on 2.4 GHz", O.enabledDisabled, help: "Otherwise background-scan based selection.", visibleWhen: { $0["self-heal", "auto-ap-channel"] == "enabled" }),
                f("self-heal", "auto-ap-channel-5G", "Automatically adjust 5 GHz channels", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("self-heal", "channelfly-5G", "Use ChannelFly on 5 GHz", O.enabledDisabled, help: nil, visibleWhen: { $0["self-heal", "auto-ap-channel-5G"] == "enabled" }),
                f("self-heal", "auto-ap-bandwidth", "Automatically adjust channel width", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("self-heal", "auto-ap-power", "Automatically adjust transmit power", O.enabledDisabled, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Background scanning", [
                f("background-scan", "enabled", "Scan 2.4 GHz", O.trueFalse, help: nil, visibleWhen: nil),
                f("background-scan", "sleep", "2.4 GHz interval (seconds)", .number(1...65535), help: nil, visibleWhen: { $0.bool("background-scan", "enabled") }),
                f("background-scan", "enabled_5g", "Scan 5 GHz", O.trueFalse, help: nil, visibleWhen: nil),
                f("background-scan", "sleep_5g", "5 GHz interval (seconds)", .number(1...65535), help: nil, visibleWhen: { $0.bool("background-scan", "enabled_5g") }),
            ]),
            ConfigSection("Client load balancing", [
                f("client-load-balancing/radio[radio-id=0]", "enabled", "Balance 2.4 GHz clients", O.trueFalse, help: nil, visibleWhen: nil),
                f("client-load-balancing/radio[radio-id=0]", "adjust-threshold", "2.4 GHz adjacent radio threshold (dB)", .number(1...100), help: nil, visibleWhen: { $0.bool("client-load-balancing/radio[radio-id=0]", "enabled") }),
                f("client-load-balancing/radio[radio-id=1]", "enabled", "Balance 5 GHz clients", O.trueFalse, help: nil, visibleWhen: nil),
                f("client-load-balancing/radio[radio-id=1]", "adjust-threshold", "5 GHz adjacent radio threshold (dB)", .number(1...100), help: nil, visibleWhen: { $0.bool("client-load-balancing/radio[radio-id=1]", "enabled") }),
            ]),
            ConfigSection("Band balancing", [
                f("band-balancing", "enabled", "Steer dual-band clients", O.trueFalse, help: nil, visibleWhen: nil),
                f("band-balancing", "percent-2_4g", "Percentage of clients on 2.4 GHz", .number(0...100), help: nil, visibleWhen: { $0.bool("band-balancing", "enabled") }),
            ]),
            ConfigSection("Radar avoidance", [
                f("scand", "enabled", "Pre-scan DFS channels for radar", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("self-heal"), ConfigWrite("background-scan"), ConfigWrite("client-load-balancing"), ConfigWrite("band-balancing"), ConfigWrite("scand")],
        applyWarning: nil
    )

    static let wips = ConfigPageSpec(
        id: "wips", title: "WIPS", subtitle: "Rogue detection and intrusion prevention", systemImage: "shield.lefthalf.filled",
        readElements: ["wips", "ips", "dhcpp"],
        sections: [
            ConfigSection("Rogue access points", [
                f("wips", "rogue-reporting", "Report rogue APs", O.trueFalse, help: nil, visibleWhen: nil),
                f("wips", "malicious-reporting", "Report malicious rogue APs only", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
            ConfigSection("Intrusion prevention", [
                f("ips", "auto-probe-limit", "Limit excessive probe requests", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("ips", "auto-authfail-block", "Temporarily block clients with repeated auth failures", O.enabledDisabled, help: nil, visibleWhen: nil),
                f("ips", "auto-authfail-blocktime", "Block time (seconds)", .number(10...1200), help: nil, visibleWhen: { $0["ips", "auto-authfail-block"] == "enabled" }),
            ]),
            ConfigSection("Rogue DHCP server detection", [
                f("dhcpp", "enabled", "Detect rogue DHCP servers", O.trueFalse, help: nil, visibleWhen: nil),
            ]),
        ],
        writes: [ConfigWrite("wips"), ConfigWrite("ips"), ConfigWrite("dhcpp")],
        applyWarning: nil
    )

    static let urlFiltering = ListPageSpec(
        id: "url-filtering", title: "URL Filtering", subtitle: "Web content filtering policies", systemImage: "hand.raised",
        component: "urlfilteringpolicy-list", element: "urlfilteringpolicy",
        columns: [ListColumn("name", "Name", width: 180), ListColumn("description", "Description")],
        fields: [
            f("urlfilteringpolicy", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("urlfilteringpolicy", "description", "Description", .text, help: nil, visibleWhen: nil),
        ],
        canAdd: false, note: "Category selections are shown in the row details; build policies in the web UI."
    )

    static let wifiCalling = ListPageSpec(
        id: "wifi-calling", title: "Wi-Fi Calling", subtitle: "Carrier ePDG profiles prioritised on the WLAN", systemImage: "phone.badge.waveform",
        component: "wificallingpolicy-list", element: "wificallingpolicy",
        columns: [ListColumn("name", "Name", width: 160), ListColumn("description", "Description"), ListColumn("priority", "Priority", width: 70), ListColumn("epdg-num", "ePDGs", width: 60)],
        fields: [
            f("wificallingpolicy", "name", "Name", .text, help: nil, visibleWhen: nil),
            f("wificallingpolicy", "description", "Description", .text, help: nil, visibleWhen: nil),
            f("wificallingpolicy", "priority", "QoS priority", .picker([ConfigOption("1", "1 (highest)"), ConfigOption("2", "2"), ConfigOption("3", "3"), ConfigOption("4", "4 (lowest)")]), help: nil, visibleWhen: nil),
        ],
        canAdd: false, note: "ePDG domains are shown in the row details."
    )

    static let services: [SettingsPage] = [
        SettingsPage(id: aaaServers.id, title: aaaServers.title, systemImage: aaaServers.systemImage, content: .list(aaaServers)),
        SettingsPage(id: "access-control", title: "Access Control", systemImage: "list.bullet.rectangle", content: .composite(config: nil, lists: [l2ACLs, l3ACLs, devicePolicies])),
        SettingsPage(id: arcPolicies.id, title: arcPolicies.title, systemImage: arcPolicies.systemImage, content: .list(arcPolicies)),
        SettingsPage(id: bonjourGateway.id, title: bonjourGateway.title, systemImage: bonjourGateway.systemImage, content: .composite(config: bonjourGateway, lists: [bonjourRules])),
        SettingsPage(id: dpsk.id, title: dpsk.title, systemImage: dpsk.systemImage, content: .list(dpsk)),
        SettingsPage(id: guestAccess.id, title: guestAccess.title, systemImage: guestAccess.systemImage, content: .composite(config: guestAccess, lists: [guestServices])),
        SettingsPage(id: hotspots.id, title: hotspots.title, systemImage: hotspots.systemImage, content: .list(hotspots)),
        SettingsPage(id: radioControl.id, title: radioControl.title, systemImage: radioControl.systemImage, content: .config(radioControl)),
        SettingsPage(id: wips.id, title: wips.title, systemImage: wips.systemImage, content: .config(wips)),
        SettingsPage(id: urlFiltering.id, title: urlFiltering.title, systemImage: urlFiltering.systemImage, content: .list(urlFiltering)),
        SettingsPage(id: wifiCalling.id, title: wifiCalling.title, systemImage: wifiCalling.systemImage, content: .list(wifiCalling)),
    ]
}
