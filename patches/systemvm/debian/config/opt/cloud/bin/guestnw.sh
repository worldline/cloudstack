#!/usr/bin/env bash
# Copyright 2012 Citrix Systems, Inc. Licensed under the
# Apache License, Version 2.0 (the "License"); you may not use this
# file except in compliance with the License.  Citrix Systems, Inc.
# reserves all rights not expressly granted by the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# Automatically generated by addcopyright.py at 04/03/2012

# guestnw.sh -- create/destroy guest network 
# @VERSION@

source /root/func.sh

lock="biglock"
locked=$(getLockFile $lock)
if [ "$locked" != "1" ]
then
    exit 1
fi

usage() {
  printf "Usage:\n %s -A  -d <dev> -i <ip address> -g <gateway> -m <network mask> -s <dns ip> -e < domain> [-f] \n" $(basename $0) >&2
  printf " %s -D -d <dev> -i <ip address> \n" $(basename $0) >&2
}


setup_dnsmasq() {
  logger -t cloud "Setting up dnsmasq for network $ip/$mask "
  # setup static 
  sed -i -e "/^[#]*dhcp-range=interface:$dev/d" /etc/dnsmasq.d/cloud.conf
  echo "dhcp-range=interface:$dev,set:interface-$dev,$ip,static" >> /etc/dnsmasq.d/cloud.conf
  # setup gateway
  sed -i -e "/^[#]*dhcp-option=tag:interface-$dev,option:router.*$/d" /etc/dnsmasq.d/cloud.conf
  if [ -n "$gw" ]
  then
    echo "dhcp-option=tag:interface-$dev,option:router,$gw" >> /etc/dnsmasq.d/cloud.conf
  fi
  # setup DNS
  sed -i -e "/^[#]*dhcp-option=tag:interface-$dev,6.*$/d" /etc/dnsmasq.d/cloud.conf
  if [ -n "$DNS" ]
  then
    echo "dhcp-option=tag:interface-$dev,6,$DNS" >> /etc/dnsmasq.d/cloud.conf
  fi
  # setup DOMAIN
  sed -i -e "/^[#]*dhcp-option=tag:interface-$dev,15.*$/d" /etc/dnsmasq.d/cloud.conf
  if [ -n "$DOMAIN" ]
  then
    echo "dhcp-option=tag:interface-$dev,15,$DOMAIN" >> /etc/dnsmasq.d/cloud.conf
  fi
  service dnsmasq restart
  sleep 1
}

desetup_dnsmasq() {
  logger -t cloud "Setting up dnsmasq for network $ip/$mask "
  
  sed -i -e "/^[#]*dhcp-option=tag:interface-$dev,option:router.*$/d" /etc/dnsmasq.d/cloud.conf
  sed -i -e "/^[#]*dhcp-option=tag:interface-$dev,6.*$/d" /etc/dnsmasq.d/cloud.conf
  sed -i -e "/^[#]*dhcp-range=interface:$dev/d" /etc/dnsmasq.d/cloud.conf
  service dnsmasq restart
  sleep 1
}


create_guest_network() {
  logger -t cloud " $(basename $0): Create network on interface $dev,  gateway $gw, network $ip/$mask "
  # setup ip configuration
  sudo ip addr add dev $dev $ip/$mask
  sudo ip link set $dev up
  sudo arping -c 3 -I $dev -A -U -s $ip $ip
  # setup rules to allow dhcp/dns request
  sudo iptables -A INPUT -i $dev -p udp -m udp --dport 67 -j ACCEPT
  sudo iptables -A INPUT -i $dev -p udp -m udp --dport 53 -j ACCEPT
  local tableName="Table_$dev"
  sudo ip route add $subnet/$mask dev $dev table $tableName proto static

  # create inbound acl chain
  if sudo iptables -N ACL_INBOUND_$ip 2>/dev/null
  then
    logger -t cloud "$(basename $0): create VPC inbound acl chain for network $ip/$mask"
    # policy drop
    sudo iptables -A ACL_INBOUND_$ip -j DROP >/dev/null
    sudo iptables -A FORWARD -o $dev -d $ip/$mask -j ACL_INBOUND_$ip
  fi
  # create outbound acl chain
  if sudo iptables -N ACL_OUTBOUND_$ip 2>/dev/null
  then
    logger -t cloud "$(basename $0): create VPC outbound acl chain for network $ip/$mask"
    sudo iptables -A ACL_OUTBOUND_$ip -j DROP >/dev/null
    sudo iptables -A FORWARD -i $dev -s $ip/$mask -j ACL_OUTBOUND_$ip
  fi

  setup_dnsmasq
}

destroy_guest_network() {
  logger -t cloud " $(basename $0): Create network on interface $dev,  gateway $gw, network $ip/$mask "
  # destroy inbound acl chain
  sudo iptables -F ACL_INBOUND_$ip 2>/dev/null
  sudo iptables -D FORWARD -o $dev -d $ip/$mask -j ACL_INBOUND_$ip  2>/dev/null
  sudo iptables -X ACL_INBOUND_$ip 2>/dev/null
  # destroy outbound acl chain
  sudo iptables -F ACL_OUTBOUND_$ip 2>/dev/null
  sudo iptables -D FORWARD -i $dev -s $ip/$mask -j ACL_OUTBOUND_$ip  2>/dev/null
  sudo iptables -X ACL_OUTBOUND_$ip 2>/dev/null

  sudo ip addr del dev $dev $ip/$mask
  sudo iptables -D INPUT -i $dev -p udp -m udp --dport 67 -j ACCEPT
  sudo iptables -D INPUT -i $dev -p udp -m udp --dport 53 -j ACCEPT
  desetup_dnsmasq
}

#set -x
iflag=0
mflag=0
nflag=0
dflag=
gflag=
Cflag=
Dflag=

op=""


while getopts 'CDn:m:d:i:g:s:e:' OPTION
do
  case $OPTION in
  C)	Cflag=1
		op="-C"
		;;
  D)	Dflag=1
		op="-D"
		;;
  n)	nflag=1
		subnet="$OPTAGR"
		;;
  m)	mflag=1
		mask="$OPTARG"
		;;
  d)	dflag=1
  		dev="$OPTARG"
  		;;
  i)	iflag=1
		ip="$OPTARG"
  		;;
  g)	gflag=1
  		gw="$OPTARG"
                ;;
  s)    sflag=1
                DNS="$OPTARG"
                ;;
  e)    eflag=1
		DOMAIN="$OPTARG"
  		;;
  ?)	usage
                unlock_exit 2 $lock $locked
		;;
  esac
done


if [ "$Cflag$Dflag$dflag" != "11" ]
then
    usage
    unlock_exit 2 $lock $locked
fi

if [ "$Cflag" == "1" ] && [ "$iflag$gflag$mflag" != "111" ]
then
    usage
    unlock_exit 2 $lock $locked
fi


if [ "$Cflag" == "1" ]
then  
  create_guest_network 
fi


if [ "$Dflag" == "1" ]
then
  destroy_guest_network
fi

unlock_exit 0 $lock $locked
