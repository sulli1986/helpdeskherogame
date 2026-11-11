extends RefCounted
## Simulated Windows command prompt for network tickets: the tech is on the phone and the user types
## what they're told. run(line, net) returns what cmd.exe would print for one command on that PC.
## `net` comes from tickets.gd _make_network: fault ("dns" | "wan" | "dhcp"), ip, gw, dc, dns_name,
## domain, host, isp_hop, ms. Supports ipconfig (/all /renew /flushdns /release), ping, nslookup <name> [server], tracert.

const NOT_FOUND := "'%s' is not recognized as an internal or external command,\noperable program or batch file."


## Flags that take a value (ping -n 2, tracert -h 10); the value isn't the target.
const VALUE_FLAGS := ["n", "l", "w", "i", "h", "j", "k", "s", "r"]


static func run(line: String, net: Dictionary) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var first := parts[0]
	if "/" in first and not first.begins_with("/"):  # cmd accepts ipconfig/all, ping/?
		parts[0] = first.get_slice("/", 0)
		parts.insert(1, first.substr(first.find("/")))
	var cmd := parts[0].to_lower().trim_suffix(".exe")
	var args: Array = []
	var switches: Array = []
	var i := 1
	while i < parts.size():
		var a: String = parts[i].to_lower()
		if a.begins_with("/") or a.begins_with("-"):
			switches.append(a.substr(1))
			if cmd != "ipconfig" and a.substr(1) in VALUE_FLAGS:
				i += 1  # skip the flag's value
		else:
			args.append(a)
		i += 1
	match cmd:
		"ipconfig":
			return _ipconfig(net, switches)
		"ping":
			return _ping(net, args) if args.size() > 0 else "Usage: ping [-t] [-n count] [-l size] target_name"
		"nslookup":
			return _nslookup(net, args) if args.size() > 0 else "(Interactive nslookup isn't available here: try nslookup <name> [server])"
		"tracert":
			return _tracert(net, args) if args.size() > 0 else "Usage: tracert [-d] [-h maximum_hops] target_name"
		"help", "?":
			return "You read commands out and the user types them. Useful here: ipconfig, ipconfig /all,\nping <ip or name>, nslookup <name> [server], tracert <ip or name>, cls"
		"exit":
			return "(Keep the user on the line until the ticket is closed.)"
		_:
			return NOT_FOUND % parts[0]


# ------------------------------------------------------------------ ipconfig
static func _ipconfig(net: Dictionary, sw: Array) -> String:
	var dhcp_down: bool = net.fault == "dhcp"
	for w in sw:
		if not w in ["all", "renew", "flushdns", "release"]:
			return "Error: unrecognized or incomplete command line."
	if "release" in sw:
		return "(Better not: releasing the lease would cut this PC off mid-call. Try ipconfig /renew.)"
	if "flushdns" in sw:
		return "Windows IP Configuration\n\nSuccessfully flushed the DNS Resolver Cache."
	if "renew" in sw and dhcp_down:
		return "Windows IP Configuration\n\nAn error occurred while renewing interface Ethernet : unable to contact your DHCP server. Request has timed out."
	var all := "all" in sw
	var s := "Windows IP Configuration\n\n"
	if all:
		s += "   Host Name . . . . . . . . . . . . : %s\n\n" % net.host
	s += "Ethernet adapter Ethernet:\n\n"
	if dhcp_down:
		s += "   Connection-specific DNS Suffix  . :\n"
		if all:
			s += "   DHCP Enabled. . . . . . . . . . . : Yes\n   Autoconfiguration Enabled . . . . : Yes\n"
		s += "   Autoconfiguration IPv4 Address. . : %s\n   Subnet Mask . . . . . . . . . . . : 255.255.0.0\n   Default Gateway . . . . . . . . . :" % net.ip
		return s
	s += "   Connection-specific DNS Suffix  . : %s\n" % net.domain
	if all:
		s += "   DHCP Enabled. . . . . . . . . . . : Yes\n"
	s += "   IPv4 Address. . . . . . . . . . . : %s\n   Subnet Mask . . . . . . . . . . . : 255.255.255.0\n   Default Gateway . . . . . . . . . : %s" % [net.ip, net.gw]
	if all:
		s += "\n   DHCP Server . . . . . . . . . . . : %s\n   DNS Servers . . . . . . . . . . . : %s" % [net.dc, net.dc]
	return s


# ------------------------------------------------------------------ name lookup
## Returns the IP for a target, "" if the name can't be resolved.
static func _resolve(net: Dictionary, target: String) -> String:
	if target.is_valid_ip_address():
		return target
	if target == "localhost":
		return "127.0.0.1"
	if net.fault == "dhcp":
		return ""  # no lease, so no DNS server configured
	if _fqdn(net, target) != "":
		return net.dc  # the DC answers for its own zone even when forwarding is broken
	return ""  # every fault in this ticket breaks external names


## The DC's full name if target names it (short name, FQDN or the AD domain), else "".
static func _fqdn(net: Dictionary, target: String) -> String:
	if target == net.dns_name.get_slice(".", 0) or target == net.dns_name:
		return net.dns_name
	return net.domain if target == net.domain else ""


## A stand-in public address for an outside name (only shown when querying a public resolver).
static func _public_ip(name: String) -> String:
	return "192.0.2.%d" % (1 + absi(name.hash()) % 250)


static func _where(net: Dictionary, ip: String) -> String:
	if ip.begins_with("127."):
		return "self"
	if net.fault == "dhcp":
		if ip == net.ip:
			return "self"
		return "lan_missing" if ip.begins_with("169.254.") else "noroute"
	if ip == net.ip:
		return "self"
	if ip == net.gw or ip == net.dc:
		return "lan"
	if ip.begins_with("192.168.1."):
		return "lan_missing"
	return "internet"


static func _ping(net: Dictionary, args: Array) -> String:
	var target: String = args[0]
	var ip := _resolve(net, target)
	if ip == "":
		return "Ping request could not find host %s. Please check the name and try again." % target
	var where := _where(net, ip)
	if where == "noroute":
		return "Pinging %s with 32 bytes of data:\nPING: transmit failed. General failure.\nPING: transmit failed. General failure.\nPING: transmit failed. General failure.\nPING: transmit failed. General failure.\n\nPing statistics for %s:\n    Packets: Sent = 4, Received = 0, Lost = 4 (100%% loss)," % [ip, ip]
	var shown: String = _fqdn(net, target) if _fqdn(net, target) != "" else target
	var s := "Pinging %s with 32 bytes of data:\n" % (ip if target == ip else "%s [%s]" % [shown, ip])
	var got := 4
	var times: Array = []
	for i in 4:
		match where:
			"self", "lan":
				s += "Reply from %s: bytes=32 time<1ms TTL=%d\n" % [ip, 64 if ip == net.gw else 128]
				times.append(0)
			"lan_missing":
				s += "Reply from %s: Destination host unreachable.\n" % net.ip
			_:
				if net.fault == "wan":
					s += "Request timed out.\n"
					got = 0
				else:
					var ms: int = net.ms + [0, 1, 0, 2][i]
					s += "Reply from %s: bytes=32 time=%dms TTL=%d\n" % [ip, ms, 64 - TRANSIT_HOPS]
					times.append(ms)
	# A "host unreachable" reply still counts as received in Windows' statistics.
	s += "\nPing statistics for %s:\n    Packets: Sent = 4, Received = %d, Lost = %d (%d%% loss)," % [ip, got, 4 - got, (4 - got) * 25]
	if not times.is_empty():
		var lo: int = times.min()
		var hi: int = times.max()
		var avg: int = roundi(float(times.reduce(func(a, b): return a + b, 0)) / times.size())
		s += "\nApproximate round trip times in milli-seconds:\n    Minimum = %dms, Maximum = %dms, Average = %dms" % [lo, hi, avg]
	return s


static func _nslookup(net: Dictionary, args: Array) -> String:
	var target: String = args[0]
	var server: String = args[1] if args.size() > 1 else ""
	if server == net.dc or _fqdn(net, server) == net.dns_name:
		server = ""  # asking the DC explicitly is the same as the default
	if server != "":
		return _nslookup_public(net, target, server)
	if net.fault == "dhcp":
		return "*** Default servers are not available\nServer:  UnKnown\nAddress:  127.0.0.1\n\n*** UnKnown can't find %s: No response from server" % target
	var s := "Server:  %s\nAddress:  %s\n\n" % [net.dns_name, net.dc]
	if target == net.dc:  # reverse lookup of the DC itself
		return s + "Name:    %s\nAddress:  %s" % [net.dns_name, target]
	if target.is_valid_ip_address() and _where(net, target) != "internet":
		return s + "*** %s can't find %s: Non-existent domain" % [net.dns_name, target]
	if _fqdn(net, target) != "":
		return s + "Name:    %s\nAddress:  %s" % [_fqdn(net, target), net.dc]
	if net.fault == "wan":
		return s + "DNS request timed out.\n    timeout was 2 seconds.\n*** Request to %s timed-out" % net.dns_name
	return s + "*** %s can't find %s: Server failed" % [net.dns_name, target]


## nslookup <name> <server> against an outside resolver (e.g. 8.8.8.8): proves whether it's the DC.
static func _nslookup_public(net: Dictionary, target: String, server: String) -> String:
	var ip: String = server if server.is_valid_ip_address() else ""
	if ip == "" or _where(net, ip) != "internet":
		if ip == "":
			return "*** Can't find address for server %s: Server failed" % server
		return "DNS request timed out.\n    timeout was 2 seconds.\nServer:  UnKnown\nAddress:  %s\n\nDNS request timed out.\n    timeout was 2 seconds.\n*** Request to UnKnown timed-out" % ip
	if net.fault != "dns":  # WAN down (or no route): nothing outside answers
		return "DNS request timed out.\n    timeout was 2 seconds.\nServer:  UnKnown\nAddress:  %s\n\nDNS request timed out.\n    timeout was 2 seconds.\n*** Request to UnKnown timed-out" % ip
	var s := "Server:  UnKnown\nAddress:  %s\n\n" % ip
	if target.is_valid_ip_address() or _fqdn(net, target) != "":
		return s + "*** UnKnown can't find %s: Non-existent domain" % target
	return s + "Non-authoritative answer:\nName:    %s\nAddress:  %s" % [target, _public_ip(target)]


## Routers between the office gateway and an internet host (sets tracert hops and ping TTL).
const TRANSIT_HOPS := 4


static func _tracert(net: Dictionary, args: Array) -> String:
	var target: String = args[0]
	var ip := _resolve(net, target)
	if ip == "":
		return "Unable to resolve target system name %s." % target
	var shown: String = _fqdn(net, target) if _fqdn(net, target) != "" else target
	var s := ("Tracing route to %s over a maximum of 30 hops\n\n" % ip if target == ip
		else "Tracing route to %s [%s]\nover a maximum of 30 hops:\n\n" % [shown, ip])
	var where := _where(net, ip)
	match where:
		"noroute":
			return s + "  1     Transmit error: code 1231.\n\nTrace complete."
		"self", "lan":
			return s + "  1    <1 ms    <1 ms    <1 ms  %s\n\nTrace complete." % ip
		"lan_missing":
			return s + "  1  %s  reports: Destination host unreachable.\n\nTrace complete." % net.ip
	s += "  1    <1 ms    <1 ms    <1 ms  %s\n" % net.gw
	if net.fault == "wan":
		for h in range(2, 6):
			s += "  %d     *        *        *     Request timed out.\n" % h
		return s + "(stopped: nothing answers past the gateway)"
	# ISP edge, two transit routers (documentation addresses), then the target.
	var hops: Array = [net.isp_hop, "198.51.100.1", "203.0.113.1", ip]
	for h in hops.size():
		var ms: int = maxi(1, net.ms - 6 + h * 2) if h < hops.size() - 1 else net.ms
		s += "  %d  %s  %s  %s  %s\n" % [h + 2, _ms(ms), _ms(ms + 1), _ms(ms), hops[h]]
	return s + "\nTrace complete."


static func _ms(n: int) -> String:
	return ("%d ms" % n).lpad(7)
