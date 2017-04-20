#!/bin/bash

# ONLY FUNCTIONS

# Policy accept
policy_accept() {
  echo "Reset default policy to \"ACCEPT\"..."
  iptables -P INPUT   ACCEPT
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD ACCEPT
}

# Policy flush and delete chains
policy_fx() {
  echo "Flush rules and delete chains..."
  iptables -F
  iptables -X
}

# Policy drop
policy_drop() {
  echo "Set default policy to \"DROP\""
  iptables -P INPUT   DROP
  iptables -P OUTPUT  DROP
  iptables -P FORWARD DROP
}

# Set ipset
function set_ipset() {
  # $1 ipset name
  # $2 ips
  # $3 type e.g. ip, net
  local SET="$1"
  local IPS=("${2}")

  if [ "$3" ]; then
    local TYPE="$3"
  else
    local TYPE="net"
  fi

  if rpm -qa | grep ipset; then
    echo "ipset installed..."
  else
    echo "ipset not installed... install ipset..."
    yum install ipset -y
  fi

  echo "### Set ipset $SET"
  echo "$SET: flush ipset"
  ipset -F $SET

  echo "$SET: delete ipset"
  ipset -X $SET

  echo "$SET: add ipset"
  ipset -N $SET hash:$TYPE

  echo "$SET: add IP in ipset"
  for IP in $IPS
  do
    echo "    $IP"
    ipset -A $SET $IP
  done

  echo "###"
  echo "Set ipset $SET: END"
}

# Spamhaus drop list
spamhaus() {
  echo "Spamhaus: START"
  local SET="SPAMHAUS"
  local FILE="/tmp/drop.lasso"
  local URL="http://www.spamhaus.org/drop/drop.lasso"

  if [ -f $FILE ];
  then
    echo "Spamhaus: remove $FILE"
    /bin/rm -f $FILE
  fi

  wget -4 $URL -O $FILE # wget http://www.spamhaus.org/drop/drop.lasso -O /tmp/drop.lasso
  local IPS="$(cat $FILE | sed -e 's/;.*//' | grep -v '^ *$' | awk '{ print $1}')"

  echo "Spamhaus: delete rule from INPUT, OUTPUT and FORWARD"
  iptables -D INPUT   -m set --match-set $SET src -j DROP
  iptables -D OUTPUT  -m set --match-set $SET dst -j DROP
  iptables -D FORWARD -m set --match-set $SET src -j DROP
  iptables -D FORWARD -m set --match-set $SET dst -j DROP

  set_ipset $SET "${IPS[@]}"

  echo "Spamhaus: add rule in INPUT, OUTPUT and FORWARD"
  iptables -I INPUT   -m set --match-set $SET src -j DROP
  iptables -I OUTPUT  -m set --match-set $SET dst -j DROP
  iptables -I FORWARD -m set --match-set $SET src -j DROP
  iptables -I FORWARD -m set --match-set $SET dst -j DROP

  echo "Spamhaus: END"
}

# CloudFlare for protected ips
cloudflare() {
  # $1 protected ips
  echo "CloudFlare: START"
  local PROTECTED_IPS=("${1}")
  local SET="CLOUDFLARE" # SET WITH CF IPS
  local PROTECTED_SET="CLOUDFLARE_PROTECTED" # SET WITH PROTECTED IPS
  local CHAIN="CLOUDFLARE"
  local FILE="/tmp/ips-v4"
  local URL="https://www.cloudflare.com/ips-v4"

  if [ -f $FILE ];
  then
    echo "CloudFlare: remove $FILE"
    /bin/rm -f $FILE
  fi

  wget -4 $URL -O $FILE # wget https://www.cloudflare.com/ips-v4 -O /tmp/ips-v4
  local IPS="$(cat $FILE | grep -v '^ *$' | awk '{ print $1}')"

  echo "CloudFlare: delete rules and chain"
  iptables -D INPUT   -p tcp -m set --match-set $PROTECTED_SET dst -m multiport --dports 80,443 -j $CHAIN
  iptables -D FORWARD -p tcp -m set --match-set $PROTECTED_SET dst -m multiport --dports 80,443 -j $CHAIN
  iptables -F $CHAIN
  iptables -X $CHAIN

  set_ipset $SET "${IPS[@]}"

  echo "CloudFlare: add chain and rules"
  iptables -N $CHAIN
  iptables -A $CHAIN         -m set --match-set $SET src                                        -j ACCEPT
  iptables -A $CHAIN                                                                            -j DROP
  iptables -I INPUT   -p tcp -m set --match-set $PROTECTED_SET dst -m multiport --dports 80,443 -j $CHAIN
  iptables -I FORWARD -p tcp -m set --match-set $PROTECTED_SET dst -m multiport --dports 80,443 -j $CHAIN

  if [ -n "$PROTECTED_IPS" ];
  then
    set_ipset $PROTECTED_SET "${PROTECTED_IPS[@]}" # "ip"
  fi

  echo "CloudFlare: END"
}