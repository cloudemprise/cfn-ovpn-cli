#!/bin/bash
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
META_DATA="169.254.169.254"
META_NTP="169.254.169.123/32"
META_DNS="$(grep -m 1 nameserver /etc/resolv.conf | sed s/'nameserver '//)/32"
#LOCAL_IPV4="$(curl -s http://${META_DATA}/latest/meta-data/local-ipv4)/32"
PUB_CIDR="10.0.128.0/18"
MAC="$(curl -s http://${META_DATA}/latest/meta-data/network/interfaces/macs/)"
VPC_CIDR="$(curl -s http://${META_DATA}/latest/meta-data/network/interfaces/macs/"$MAC"/vpc-ipv4-cidr-block)"
VPN_CIDR_UDP="10.100.10.0/24"
VPN_CIDR_TCP="10.100.20.0/24"
VPN_CIDR="10.100.0.0/16"
NIC="$(ip -o -4 route show to default | awk '{print $5}')"
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Clear ipv4 chains
iptables -F
iptables -F -t nat
iptables -X
iptables -X -t nat
# Clear ipv6 chains
ip6tables -F
ip6tables -F -t nat
ip6tables -X
ip6tables -X -t nat
# Set default ipv4 policy
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP
# Set default ipv6 policy
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# loopback  policy
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# drop and log incoming invalid packets 
iptables -N IPTlogDROPinINVALID
iptables -A INPUT -m conntrack --ctstate INVALID -j IPTlogDROPinINVALID
iptables -A IPTlogDROPinINVALID -j LOG --log-prefix "IPTlogDROPin__:_INVALID:"
iptables -A IPTlogDROPinINVALID -j DROP
# drop and log outgoing invalid packets 
iptables -N IPTlogDROPoutINVALID
iptables -A OUTPUT -m conntrack --ctstate INVALID -j IPTlogDROPoutINVALID
iptables -A IPTlogDROPoutINVALID -j LOG --log-prefix "IPTlogDROPout_:_INVALID:"
iptables -A IPTlogDROPoutINVALID -j DROP
# drop and log forwarded invalid packets 
iptables -N IPTlogDROPfrwINVALID
iptables -A FORWARD -m conntrack --ctstate INVALID -j IPTlogDROPfrwINVALID
iptables -A IPTlogDROPfrwINVALID -j DROP
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# accept all established packets 
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# accept, log and limit incoming pings
iptables -N IPTlogPASSinICMPreq
iptables -A INPUT -d $PUB_CIDR -p icmp --icmp-type echo-request -i "$NIC" -m limit --limit 2/s --limit-burst 2 -j IPTlogPASSinICMPreq
iptables -A IPTlogPASSinICMPreq -j LOG --log-prefix "IPTlogPASSin__:_PING___:"
iptables -A IPTlogPASSinICMPreq -j ACCEPT
# allow and log local outgoing pings
iptables -N IPTlogPASSoutICMPreq
iptables -A OUTPUT -s $PUB_CIDR -p icmp --icmp-type echo-request -o "$NIC" -j IPTlogPASSoutICMPreq
iptables -A IPTlogPASSoutICMPreq -j LOG --log-prefix "IPTlogPASSout_:_PING___:"
iptables -A IPTlogPASSoutICMPreq -j ACCEPT
# accept forwarded ping requests from VPC hosts
iptables -N IPTlogPASSfrwICMPreq
iptables -A FORWARD -s $VPN_CIDR -p icmp --icmp-type echo-request -o "$NIC" -j IPTlogPASSfrwICMPreq
iptables -A IPTlogPASSfrwICMPreq -j LOG --log-prefix "IPTlogPASSfrw_:_PING___:"
iptables -A IPTlogPASSfrwICMPreq -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow output local dhcp requests to VPC servers
iptables -N IPTlogPASSoutDHCP
iptables -A OUTPUT -s $PUB_CIDR -d "$VPC_CIDR" -p udp --sport 68 --dport 67 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutDHCP
iptables -A IPTlogPASSoutDHCP -j LOG --log-prefix "IPTlogPASSout_:_DHCP___:"
iptables -A IPTlogPASSoutDHCP -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow local ntp sync requests to metadata services
iptables -N IPTlogPASSoutNTP
iptables -A OUTPUT -s $PUB_CIDR -d $META_NTP -p udp --sport 1024:65535 --dport 123 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutNTP
#iptables -A IPTlogPASSoutNTP -j LOG --log-prefix "IPTlogPASSout_:_NTP____:"
iptables -A IPTlogPASSoutNTP -j ACCEPT
# allow forwarded ntp requests from VPN hosts
iptables -N IPTlogPASSfrwNTP
iptables -A FORWARD -s $VPN_CIDR -p udp --sport 1024:65535 --dport 123 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwNTP
iptables -A IPTlogPASSfrwNTP -j LOG --log-prefix "IPTlogPASSfrw_:_NTP____:"
iptables -A IPTlogPASSfrwNTP -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow local dns requests to metadata services
iptables -N IPTlogPASSoutDNS
iptables -A OUTPUT -s $PUB_CIDR -d "$META_DNS" -p udp --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutDNS
#iptables -A IPTlogPASSoutDNS -j LOG --log-prefix "IPTlogPASSout_:_DNS____:"
iptables -A IPTlogPASSoutDNS -j ACCEPT
# allow forwarded dns requests from VPN hosts
iptables -N IPTlogPASSfrwDNS
iptables -A FORWARD -s $VPN_CIDR -p udp --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwDNS
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwDNS
iptables -A IPTlogPASSfrwDNS -j LOG --log-prefix "IPTlogPASSfrw_:_DNS____:"
iptables -A IPTlogPASSfrwDNS -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow http requests from any LOCAL sources (nlb health checks)
iptables -N IPTlogPASSinNLB
iptables -A INPUT -s $PUB_CIDR -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport http -m conntrack --ctstate NEW -i "$NIC" -j IPTlogPASSinNLB
#iptables -A IPTlogPASSinNLB -j LOG --log-prefix "IPTlogPASSin__:_NLB____:"
iptables -A IPTlogPASSinNLB -j ACCEPT
# allow Instance Metadata Service from LOCAL subnets only
iptables -N IPTlogPASSoutIMDS
iptables -A OUTPUT -s $PUB_CIDR -d ${META_DATA}/32 -p tcp --syn --sport 1024:65535 --dport http  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutIMDS
#iptables -A IPTlogPASSoutIMDS -j LOG --log-prefix "IPTlogPASSout_:_IMDS___:"
iptables -A IPTlogPASSoutIMDS -j ACCEPT
# allow output local http/s traffic
iptables -N IPTlogPASSoutHTTPS
iptables -A OUTPUT -s $PUB_CIDR ! -d ${META_DATA}/32 -p tcp --syn --sport 1024:65535 --dport http  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutHTTPS
iptables -A OUTPUT -s $PUB_CIDR ! -d ${META_DATA}/32 -p tcp --syn --sport 1024:65535 --dport https -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutHTTPS
iptables -A IPTlogPASSoutHTTPS -j LOG --log-prefix "IPTlogPASSout_:_HTTPS__:"
iptables -A IPTlogPASSoutHTTPS -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow forwarded http/s traffic from VPN hosts
iptables -N IPTlogPASSfrwHTTPS
iptables -A FORWARD -s $VPN_CIDR ! -d ${META_DATA}/32 -p tcp --syn --sport 1024:65535 --dport http  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwHTTPS
iptables -A FORWARD -s $VPN_CIDR ! -d ${META_DATA}/32 -p tcp --syn --sport 1024:65535 --dport https -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwHTTPS
iptables -A IPTlogPASSfrwHTTPS -j LOG --log-prefix "IPTlogPASSfrw_:_HTTPS__:"
iptables -A IPTlogPASSfrwHTTPS -j ACCEPT
#~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# block spurious android/chrome tracking udp 443 trafic
iptables -N IPTlogDROPfrwHTTPS
iptables -A FORWARD -s $VPN_CIDR -p udp --sport 1024:65535 --dport 443 -m conntrack --ctstate NEW -o "$NIC" -j IPTlogDROPfrwHTTPS
#iptables -A IPTlogDROPfrwHTTPS -j LOG --log-prefix "IPTlogDROPfrw_:_HTTPS__:"
iptables -A IPTlogDROPfrwHTTPS -j DROP
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow incoming ssh traffic from any source
iptables -N IPTlogPASSinSSH
iptables -A INPUT -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport 22 -m conntrack --ctstate NEW -i "$NIC" -m limit --limit 3/min --limit-burst 2 -j IPTlogPASSinSSH
iptables -A IPTlogPASSinSSH -j LOG --log-prefix "IPTlogPASSin__:_SSH____:"
iptables -A IPTlogPASSinSSH -j ACCEPT
# allow outgoing ssh traffic only within VPC
iptables -N IPTlogPASSoutSSH
iptables -A OUTPUT -s $PUB_CIDR -d "$VPC_CIDR" -p tcp --syn --sport 1024:65535 --dport 22  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSoutSSH
iptables -A IPTlogPASSoutSSH -j LOG --log-prefix "IPTlogPASSout_:_SSH____:"
iptables -A IPTlogPASSoutSSH -j ACCEPT
# allow forwarded ssh traffic from VPN hosts
iptables -N IPTlogPASSfrwSSH
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 22  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwSSH
iptables -A IPTlogPASSfrwSSH -j LOG --log-prefix "IPTlogPASSfrw_:_SSH____:"
iptables -A IPTlogPASSfrwSSH -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow forwarded imap/smtp traffic from VPN hosts
iptables -N IPTlogPASSfrwMAIL
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 993  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwMAIL
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 465  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwMAIL
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 587  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwMAIL
iptables -A IPTlogPASSfrwMAIL -j LOG --log-prefix "IPTlogPASSfrw_:_MAIL___:"
iptables -A IPTlogPASSfrwMAIL -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow forwarded google play store traffic from VPN hosts
iptables -N IPTlogPASSfrwGPS
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 5228  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwGPS
iptables -A IPTlogPASSfrwGPS -j LOG --log-prefix "IPTlogPASSfrw_:_GPS____:"
iptables -A IPTlogPASSfrwGPS -j ACCEPT
#~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# allow forwarded (SimCard) Highway Addressable Remote Transducer Protocol traffic from VPN hosts
iptables -N IPTlogPASSfrwHIP
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 5094  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwHIP
iptables -A IPTlogPASSfrwHIP -j LOG --log-prefix "IPTlogPASSfrw_:_HART-IP:"
iptables -A IPTlogPASSfrwHIP -j ACCEPT
#~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
# allow forwarded XMPP vodafone service traffic from VPN hosts
iptables -N IPTlogPASSfrwXMPP
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 5222  -m conntrack --ctstate NEW -o "$NIC" -j IPTlogPASSfrwXMPP
iptables -A IPTlogPASSfrwXMPP -j LOG --log-prefix "IPTlogPASSfrw_:_XMPP___:"
iptables -A IPTlogPASSfrwXMPP -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# allow VPN handshake (tcp/udp) requests from any source
iptables -N IPTlogPASSinVPN
iptables -A INPUT -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport 1194 -m conntrack --ctstate NEW -i "$NIC" -j IPTlogPASSinVPN
iptables -A INPUT -d $PUB_CIDR -p udp --sport 1024:65535 --dport 1194 -m conntrack --ctstate NEW -i "$NIC" -j IPTlogPASSinVPN
iptables -A IPTlogPASSinVPN -j LOG --log-prefix "IPTlogPASSin__:_VPN____:"
iptables -A IPTlogPASSinVPN -j ACCEPT
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# NAT only VPN traffic
iptables -t nat -N IPTlogMASQnatPOST
iptables -t nat -A POSTROUTING -s $VPN_CIDR_UDP -m conntrack --ctstate NEW -o "$NIC" -j IPTlogMASQnatPOST
iptables -t nat -A POSTROUTING -s $VPN_CIDR_TCP -m conntrack --ctstate NEW -o "$NIC" -j IPTlogMASQnatPOST
iptables -t nat -A IPTlogMASQnatPOST -j MASQUERADE
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# drop and log all unknown traffic
iptables -A INPUT -j LOG --log-prefix "IPTlogDROPin__:_UNKWN__:"
iptables -A OUTPUT -j LOG --log-prefix "IPTlogDROPout_:_UNKWN__:"
iptables -A FORWARD -j LOG --log-prefix "IPTlogDROPfrw_:_UNKWN__:"
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Save rules
service iptables save
# /etc/init.d/iptables save
service ip6tables save
# /etc/init.d/ip6tables save

