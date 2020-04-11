#!/bin/bash
#--

META_NTP="169.254.169.123/32"
META_DNS="$(grep -m 1 nameserver /etc/resolv.conf | sed s/'nameserver '//)/32"
LOCAL_IPV4="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)/32"
PUB_CIDR="10.0.128.0/18"
MAC="$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/)"
VPC_CIDR="$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/"$MAC"/vpc-ipv4-cidr-block)"
VPN_CIDR_UDP="10.100.10.0/24"
VPN_CIDR_TCP="10.100.20.0/24"
VPN_CIDR="10.100.0.0/16"
NIC="$(ip -o -4 route show to default | awk '{print $5}')"

#--
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
# loopback  policy
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
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
# accept all established packets 
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# accept, log and limit incoming pings
iptables -N IPTlogPASSinICMPreq
iptables -A INPUT -d $PUB_CIDR -p icmp --icmp-type echo-request -i $NIC -m limit --limit 2/s --limit-burst 2 -j IPTlogPASSinICMPreq
iptables -A IPTlogPASSinICMPreq -j LOG --log-prefix "IPTlogPASSin__:_PING___:"
iptables -A IPTlogPASSinICMPreq -j ACCEPT
# allow and log local outgoing pings
iptables -N IPTlogPASSoutICMPreq
iptables -A OUTPUT -s $PUB_CIDR -p icmp --icmp-type echo-request -o $NIC -j IPTlogPASSoutICMPreq
iptables -A IPTlogPASSoutICMPreq -j LOG --log-prefix "IPTlogPASSout_:_PING___:"
iptables -A IPTlogPASSoutICMPreq -j ACCEPT
# accept forwarded ping requests from VPC hosts
iptables -A FORWARD -s $VPN_CIDR -p icmp --icmp-type echo-request -o $NIC -j ACCEPT
# allow output local dhcp requests to VPC servers
iptables -A OUTPUT -s $PUB_CIDR -d $VPC_CIDR -p udp --sport 68 --dport 67 -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# allow time sync requests to metadata services
iptables -A OUTPUT -s $PUB_CIDR -d $META_NTP -p udp --sport 1024:65535 --dport 123 -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# allow dns requests to metadata services
iptables -A OUTPUT -s $PUB_CIDR -d $META_DNS -p udp --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# accept forwarded dns requests from VPN hosts
iptables -A FORWARD -s $VPN_CIDR -p udp --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o $NIC -j ACCEPT
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 53 -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# allow http requests from any local sources (nlb)
iptables -N IPTlogPASSinNLB
iptables -A INPUT -s $PUB_CIDR -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport http -m conntrack --ctstate NEW -i $NIC -j IPTlogPASSinNLB
#iptables -A IPTlogPASSinNLB -j LOG --log-prefix "IPTlogPASSin__:_NLB____:"
iptables -A IPTlogPASSinNLB -j ACCEPT
# allow http requests from any source
iptables -N IPTlogPASSinHTTPS
iptables -A INPUT ! -s $PUB_CIDR -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport http -m conntrack --ctstate NEW -i $NIC -j IPTlogPASSinHTTPS
iptables -A IPTlogPASSinHTTPS -j LOG --log-prefix "IPTlogPASSin__:_HTTPS__:"
iptables -A IPTlogPASSinHTTPS -j ACCEPT
# allow output local http/s traffic
iptables -N IPTlogPASSoutHTTPS
iptables -A OUTPUT -s $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport http  -m conntrack --ctstate NEW -o $NIC -j IPTlogPASSoutHTTPS
iptables -A OUTPUT -s $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport https -m conntrack --ctstate NEW -o $NIC -j IPTlogPASSoutHTTPS
iptables -A IPTlogPASSoutHTTPS -j LOG --log-prefix "IPTlogPASSout_:_HTTPS__:"
iptables -A IPTlogPASSoutHTTPS -j ACCEPT
# accept forwarded http/s traffic from VPN hosts
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport http  -m conntrack --ctstate NEW -o $NIC -j ACCEPT
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport https -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# allow incoming ssh traffic from any source
iptables -N IPTlogPASSinSSH
iptables -A INPUT -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport 22 -m conntrack --ctstate NEW -i $NIC -j IPTlogPASSinSSH
iptables -A IPTlogPASSinSSH -j LOG --log-prefix "IPTlogPASSin__:_SSH____:"
iptables -A IPTlogPASSinSSH -j ACCEPT
# allow outgoing ssh traffic only within VPC
iptables -A OUTPUT -s $PUB_CIDR -d $VPC_CIDR -p tcp --syn --sport 1024:65535 --dport 22  -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# accept forwarded ssh traffic from VPN hosts
iptables -A FORWARD -s $VPN_CIDR -p tcp --syn --sport 1024:65535 --dport 22  -m conntrack --ctstate NEW -o $NIC -j ACCEPT
# allow VPN handshake requests from any source
iptables -N IPTlogPASSinVPN
iptables -A INPUT -d $PUB_CIDR -p tcp --syn --sport 1024:65535 --dport 1194 -m conntrack --ctstate NEW -i $NIC -j IPTlogPASSinVPN
iptables -A INPUT -d $PUB_CIDR -p udp --sport 1024:65535 --dport 1194 -m conntrack --ctstate NEW -i $NIC -j IPTlogPASSinVPN
iptables -A IPTlogPASSinVPN -j LOG --log-prefix "IPTlogPASSin__:_VPN____:"
iptables -A IPTlogPASSinVPN -j ACCEPT
# nat only VPN traffic
iptables -t nat -N IPTlogMASQnatPOST
iptables -t nat -A POSTROUTING -s $VPN_CIDR_UDP -m conntrack --ctstate NEW -o $NIC -j IPTlogMASQnatPOST
iptables -t nat -A POSTROUTING -s $VPN_CIDR_TCP -m conntrack --ctstate NEW -o $NIC -j IPTlogMASQnatPOST
iptables -t nat -A IPTlogMASQnatPOST -j MASQUERADE
# drop and log all unknown traffic
iptables -A INPUT -j LOG --log-prefix "IPTlogDROPin__:_UNKWN__:"
iptables -A OUTPUT -j LOG --log-prefix "IPTlogDROPout_:_UNKWN__:"
iptables -A FORWARD -j LOG --log-prefix "IPTlogDROPfrw_:_UNKWN__:"

# Save rules
service iptables save
# /etc/init.d/iptables save
service ip6tables save
# /etc/init.d/ip6tables save

