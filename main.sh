#!/bin/sh

# cni 插件 brhost
# pod 直连宿主机网络
# 解决 macvlan 不能与宿主机通信的限制
# 需要后台运行 dhcp daemon
# https://github.com/containernetworking/plugins/tree/main/plugins/ipam/dhcp/systemd
stdin=$(mktemp)
plugin_name=brhost
cat >"${stdin}"

debug_tty=`cat "${stdin}" | jq -r '.debug'`

if [[ -n "${debug_tty}" ]]; then
    env > "${debug_tty}"
    cat "${stdin}" > "${debug_tty}"
fi

cni_ver="$(cat ${stdin} | jq -r '.cniVersion')"
cur=$(dirname ${0})
cur=$(
	cd ${cur}
	pwd
)

br_name=cni-brhost

LOCK_FILE="/tmp/${br_name}.lock"

# 如果 debug_tty = '' 创建一个临时文件
# 省的后面 if else 了
if [[ -z "${debug_tty}" ]]; then
    debug_tty=`mktemp`
fi

echo '=================================' > "${debug_tty}"

case "${CNI_COMMAND}" in
"ADD")

	tmp1=$(mktemp)
	cat <<EOF | "${CNI_PATH}/bridge" >"${tmp1}"
{
    "cniVersion": "${cni_ver}",
    "name": "bridge",
    "type": "bridge",
    "ipam": {},
    "hairpinMode": true,
    "bridge" :"${br_name}"
}
EOF

	# 二层打通 同时保留ip地址
	flock "${LOCK_FILE}" "${CNI_PATH}/setup_br.sh" >&2

	tmp2=$(mktemp)
	cat <<EOF | "${CNI_PATH}/dhcp" >"${tmp2}"
{
    "cniVersion": "${cni_ver}",
    "name": "bridge",
    "type": "bridge",
    "ipam": {},
    "hairpinMode": true,
    "bridge" :"${br_name}"
}
EOF

	python3 -c "
import json
with open('${tmp1}') as f:
    tmp1 = json.load(f)
    
with open('${tmp2}') as f:
    tmp2 = json.load(f)

res = {}
res['cniVersion'] = '${cni_ver}'
res['interfaces'] = tmp1['interfaces']
res['ips'] = tmp2['ips']
res['routes'] = tmp2['routes']
print(json.dumps(res))
" | tee "${debug_tty}"

	ct_ip=$(cat ${tmp2} | jq -r '.ips[0].address')
	gw=$(cat ${tmp2} | jq -r '.ips[0].gateway')
	ip netns exec $(basename ${CNI_NETNS}) ip a add "${ct_ip}" dev "${CNI_IFNAME}"

    # 这里默认路由用宿主机的ip
    # 如果用dhcp分配的话 无法访问 kube-proxy 创建的虚拟ip
    # 因为访问虚拟ip的包就直接发到dhcp分配的网关了
    lan_ip=`ip a show dev ${br_name} | grep -E 'inet[^6]' | awk '{print $2}'`
    lan_ip=`dirname "${lan_ip}"`
	ip netns exec $(basename ${CNI_NETNS}) ip route add default via "${lan_ip}"

	rm -rf "${stdin}" "${tmp1}" "${tmp2}"

	;;
"DEL")
	cat <<EOF | "${CNI_PATH}/dhcp" | tee "${debug_tty}"
{
    "name": "${plugin_name}",
    "ipam": {"type": "dhcp"}
}
EOF
	;;
"CHECK")
	cat "${stdin}" | "${CNI_PATH}/bridge" | tee "${debug_tty}"
	;;
"VERSION")
    # CNI_COMMAND=VERSION crio 传过来的 CNI_PATH 是 dummy 不是真正的 cni path
	cat "${stdin}" | "/opt/cni/bin/bridge" | tee "${debug_tty}"
	;;

esac

if [[ -f "${debug_tty}" ]]; then
    rm -rf "${debug_tty}"
fi
