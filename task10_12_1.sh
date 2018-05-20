#!/bim/bash

source $(dirname $(realpath $0))/config
mkdir $(dirname $(realpath $0))/networks
mkdir -p $(dirname $(realpath $0))/config-drives/vm1-config
mkdir -p $(dirname $(realpath $0))/config-drives/vm2-config


MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`

#external_net
cat > $(dirname $(realpath $0))/networks/external.xml << EOF
<network>
  <name>$EXTERNAL_NET_NAME</name>
  <forward mode='nat'/>
  <ip address='$EXTERNAL_NET_HOST_IP' netmask='$EXTERNAL_NET_MASK'>
    <dhcp>
    <range start='${EXTERNAL_NET}.100' end='${EXTERNAL_NET}.254'/>
        <host mac='$MAC' name='vm1' ip='$VM1_EXTERNAL_IP'/>
    </dhcp>
  </ip>
</network>
EOF

#internal_net
cat > $(dirname $(realpath $0))/networks/internal.xml << EOF
<network>
    <name>$INTERNAL_NET_NAME</name>
</network>
EOF

#management_net
cat > $(dirname $(realpath $0))/networks/management.xml << EOF
<network>
    <name>$MANAGEMENT_NET_NAME</name>
    <ip address="$MANAGEMENT_HOST_IP" netmask="$MANAGEMENT_NET_MASK">
   </ip>
</network>
EOF

virsh net-define $(dirname $(realpath $0))/networks/external.xml
virsh net-define $(dirname $(realpath $0))/networks/internal.xml
virsh net-define $(dirname $(realpath $0))/networks/management.xml

virsh net-start external
virsh net-start internal
virsh net-start management

#vms
#vm1
echo  $(dirname $VM1_HDD)
mkdir -p $(dirname $VM1_HDD)
echo $(dirname $VM1_CONFIG_ISO)
mkdir -p $(dirname $VM1_CONFIG_ISO)

cat > $(dirname $(realpath $0))/vm1.xml << EOF
<domain type='$VM_VIRT_TYPE'>
  <name>$VM1_NAME</name>
  <memory unit='MiB'>$VM1_MB_RAM</memory>
  <vcpu placement='static'>$VM1_NUM_CPU</vcpu>
  <os>
    <type>$VM_TYPE</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$VM1_HDD'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$VM1_CONFIG_ISO'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <mac address='$MAC'/>
      <source network='external'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <source network='internal'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <source network='management'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/0'/>
      <target port='0'/>
    </serial>
    <console type='pty' tty='/dev/pts/0'>
      <source path='/dev/pts/0'/>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>
EOF

#vm2
echo  $(dirname $VM2_HDD)
mkdir -p $(dirname $VM2_HDD)
echo $(dirname $VM2_CONFIG_ISO)
mkdir -p $(dirname $VM2_CONFIG_ISO)

cat > $(dirname $(realpath $0))/vm2.xml << EOF
<domain type='$VM_VIRT_TYPE'>
  <name>$VM2_NAME</name>
  <memory unit='MiB'>$VM2_MB_RAM</memory>
  <vcpu placement='static'>$VM2_NUM_CPU</vcpu>
  <os>
    <type>$VM_TYPE</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$VM2_HDD'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$VM2_CONFIG_ISO'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='internal'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <source network='management'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/0'/>
      <target port='0'/>
    </serial>
    <console type='pty' tty='/dev/pts/0'>
       <source path='/dev/pts/0'/>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>
EOF

wget -O $(dirname $VM1_HDD)/ubunut-server-16.04.qcow2 $VM_BASE_IMAGE 

cp $(dirname $VM1_HDD)/ubunut-server-16.04.qcow2 $VM1_HDD
cp $(dirname $VM1_HDD)/ubunut-server-16.04.qcow2 $VM2_HDD

#iso
#vm1
cat > $(dirname $(realpath $0))/config-drives/vm1-config/meta-data << EOF
instance-id: vm1-host001
hostname: $VM1_NAME 
local-hostname: $VM1_NAME
network-interfaces: |
  auto $VM1_EXTERNAL_IF
  iface $VM1_EXTERNAL_IF inet dhcp

  auto $VM1_INTERNAL_IF
  iface $VM1_INTERNAL_IF inet static
   address $VM1_INTERNAL_IP
   netmask $INTERNAL_NET_MASK

  auto $VM1_MANAGEMENT_IF
  iface $VM1_MANAGEMENT_IF inet static
  address $VM1_MANAGEMENT_IP
  netmask $MANAGEMENT_NET_MASK
EOF

SSHKEY=$(<$SSH_PUB_KEY)

cat > $(dirname $(realpath $0))/config-drives/vm1-config/user-data << EOF
#cloud-config
password: dima
ssh_pwauth: True
chpasswd: { expire: False }
ssh_authorized_keys:
- $(<$SSH_PUB_KEY)
runcmd:
- echo 1 > /proc/sys/net/ipv4/ip_forward
- iptables -A INPUT -i lo -j ACCEPT
- ifconfig
- iptables -A FORWARD -i $VM1_INTERNAL_IF -o $VM1_EXTERNAL_IF -j ACCEPT
- iptables -t nat -A POSTROUTING -o $VM1_EXTERNAL_IF -s $INTERNAL_NET_IP/$INTERNAL_NET_MASK -j MASQUERADE
- iptables -A FORWARD -i $VM1_EXTERNAL_IF -m state --state ESTABLISHED,RELATED -j ACCEPT
- iptables -A FORWARD -i $VM1_EXTERNAL_IF -o ens4 -j REJECT
- ip link add $VXLAN_IF type vxlan id $VID remote $VM2_INTERNAL_IP local $VM1_INTERNAL_IP dstport 4789
- ip link set up dev $VXLAN_IF
- ip addr add $VM1_VXLAN_IP/255.255.255.0 dev $VXLAN_IF broadcast +
EOF

#vm2
cat > $(dirname $(realpath $0))/config-drives/vm2-config/meta-data << EOF
nstance-id: vm2-host001
hostname: $VM2_NAME
local-hostname: $VM2_NAME
EOF

cat > $(dirname $(realpath $0))/config-drives/vm2-config/user-data << EOF
#cloud-config
password: dima
ssh_pwauth: True
chpasswd: { expire: False }

ssh_authorized_keys:
- $(<$SSH_PUB_KEY)

packages:
 - docker-ce
apt:
 sources:
   docker-ce.list:
     source: "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable"
     keyid: 0EBFCD88

runcmd:
- ip link add $VXLAN_IF type vxlan id $VID remote $VM1_INTERNAL_IP local $VM2_INTERNAL_IP dstport 4789
- ip link set up dev $VXLAN_IF
- ip addr add $VM2_VXLAN_IP/255.255.255.0 dev $VXLAN_IF broadcast +
EOF

cat > $(dirname $(realpath $0))/config-drives/vm2-config/network-config << EOF
  version: 1
  config:
  - type: physical
    name: $VM2_INTERNAL_IF
    subnets:
    - type: static
      address: $VM2_INTERNAL_IP
      netmask: $INTERNAL_NET_MASK
      gateway: $VM1_INTERNAL_IP
  - type: physical
    name: $VM2_MANAGEMENT_IF
    subnets:
    - type: static
      address: $VM2_MANAGEMENT_IP
      netmask: $MANAGEMENT_NET_MASK
  - type: nameserver
    address:
      - $VM_DNS
EOF

mkisofs -o "$VM1_CONFIG_ISO" -V cidata -r -J --quiet $(dirname $(realpath $0))/config-drives/vm1-config

mkisofs -o "$VM2_CONFIG_ISO" -V cidata -r -J --quiet $(dirname $(realpath $0))/config-drives/vm2-config

virsh define $(dirname $(realpath $0))/vm1.xml
virsh define $(dirname $(realpath $0))/vm2.xml

virsh start $VM1_NAME
var1=`nc -w 2 $VM1_EXTERNAL_IP 22 </dev/null >/dev/null; echo $?`
while [ $var1 -gt 0 ]
do
#echo $var1
var1=`nc -w 2 $VM1_EXTERNAL_IP 22 </dev/null >/dev/null; echo $?`
done
virsh start $VM2_NAME

