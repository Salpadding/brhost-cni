# brhost cni

使用 shell 实现的 cni 

依赖 jq  bash
kube-proxy 建议使用 ipvs 模式

安装

1. 需要安装官方的cni插件 https://github.com/containernetworking/plugins

2. 配置好 cni-dhcp daemon https://github.com/containernetworking/plugins/tree/main/plugins/ipam/dhcp/systemd

3. 安装到你的 CNI_PATH, crio 的 CNI_PATH 是 /usr/lib/cni


```sh
ln -sf `pwd`/main.sh /opt/cni/bin/brhost
ln -sf `pwd`/setup_br.sh /opt/cni/bin/setup_br.sh

cat <<EOF > /etc/cni/net.d/10-brhost.conflist
{
  "cniVersion": "0.3.1",
  "name": "brhost",
  "plugins": [
    {
      "type": "brhost",
      "ipam": {},
      "debug": ""
    }
  ]
}
EOF
```
