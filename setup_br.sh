#!/bin/sh

br_name=cni-brhost

setup_bridge() {
    local master="$(ip link show master "${br_name}" type '')"
    if [[ -n "${master}" ]]; then
        return
    fi

    local en="$(ip route | grep '^default' | awk '{print $5}')"

    local lan_ip=$(ip a | grep "${en}" | grep inet | awk '{print $2}')
    local gw=

    while [[ -z "${gw}" ]]; do
        gw="$(ip route | grep '^default' | awk '{print $3}')"
        sleep 1
    done

    systemctl stop dhcpcd
    ip link set "${en}" master "${br_name}"
    ip a del "${lan_ip}" dev "${en}"
    ip route del default
    ip a add "${lan_ip}" dev "${br_name}"
    ip route add default via "${gw}"

}

setup_bridge
