#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp


##### Neutron Networking Service #####

cat << _EOF_ > ./tmp/neutrondb
mysql -u root -p$PASSWORD -e "SHOW DATABASES;" | grep neutron > /dev/null 2>&1 && echo "neutron database already exists" || mysql -u root -p$PASSWORD -e "CREATE DATABASE neutron; GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CONT_MAN_IP < ./tmp/neutrondb

openstack user list | grep neutron > /dev/null 2>&1 && echo "neutron user already exists" || openstack user create --domain default --password $PASSWORD neutron
openstack role add --project service --user neutron admin
openstack service list | grep neutron > /dev/null 2>&1 && echo "neutron service already exists" || openstack service create --name neutron --description "OpenStack Networking service" network
openstack endpoint list | grep public | grep neutron > /dev/null 2>&1 && echo "neutron public endpoint already exists" || openstack endpoint create --region RegionOne network public http://${CONT_MAN_IP}:9696
openstack endpoint list | grep internal | grep neutron > /dev/null 2>&1 && echo "neutron internal endpoint exists" || openstack endpoint create --region RegionOne network internal http://${CONT_MAN_IP}:9696
openstack endpoint list | grep admin | grep neutron > /dev/null 2>&1 && echo "neutron admin endpoint already exists" || openstack endpoint create --region RegionOne neutron admin http://${CONT_MAN_IP}:9696

ssh $CONT_MAN_IP yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch

ssh $CONT_MAN_IP [ ! -f /etc/neutron/neutron.conf.orig ] && cp -v /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
cat << _EOF_ > ./tmp/neutron.conf
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:${PASSWORD}@${CONT_MAN_IP}
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
[agent]
[cors]
[database]
connection = mysql+pymysql://neutron:${PASSWORD}@${CONT_MAN_IP}/neutron
[keystone_authtoken]
auth_uri = http://${CONT_MAN_IP}:5000
auth_url = http://${CONT_MAN_IP}:35357
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $PASSWORD
[matchmaker_redis]
[nova]
auth_url = http://${CONT_MAN_IP}:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $PASSWORD
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[quotas]
[ssl]
_EOF_
scp ./tmp/neutron.conf $CONT_MAN_IP:/etc/neutron/neutron.conf

ssh $CONT_MAN_IP [ ! -f /etc/neutron/plugins/ml2/ml2_conf.ini.orig ] && cp -v /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
cat << _EOF_ > ./tmp/ml2_conf.ini
[DEFAULT]
[l2pop]
[ml2]
type_drivers=vxlan,flat
tenant_network_types=vxlan
mechanism_drivers=openvswitch
extension_drivers=port_security,qos
path_mtu=0
[ml2_type_flat]
flat_networks=*
[ml2_type_geneve]
[ml2_type_gre]
[ml2_type_vlan]
[ml2_type_vxlan]
vni_ranges=10:1000
vxlan_group=224.0.0.1
[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
enable_security_group=True
enable_ipset = true
_EOF_
scp ./tmp/ml2_conf.ini $CONT_MAN_IP:/etc/neutron/plugins/ml2/ml2_conf.ini

ssh $CONT_MAN_IP [ ! -f /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig ] && cp -v /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig
cat << _EOF_ > ./tmp/openvswitch_agent.ini
[DEFAULT]
[agent]
tunnel_types=vxlan
vxlan_udp_port=4789
l2_population=False
drop_flows_on_start=False
[network_log]
[ovs]
integration_bridge=br-int
tunnel_bridge=br-tun
local_ip=$CONT_MAN_IP
bridge_mappings=extnet:br-ex
[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
[xenapi]
_EOF_
scp ./tmp/openvswitch_agent.ini $CONT_MAN_IP:/etc/neutron/plugins/ml2/openvswitch_agent.ini

ssh $CONT_MAN_IP [ ! -f /etc/neutron/l3_agent.ini.orig ] && cp -v /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig
cat << _EOF_ > ./tmp/l3_agent.ini
[DEFAULT]
interface_driver=neutron.agent.linux.interface.OVSInterfaceDriver
agent_mode=legacy
debug=False
[agent]
[ovs]
_EOF_
scp ./tmp/l3_agent.ini $CONT_MAN_IP:/etc/neutron/l3_agent.ini

ssh $CONT_MAN_IP [ ! -f /etc/neutron/dhcp_agent.ini.orig ] && cp -v /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig
cat << _EOF_ > ./tmp/dhcp_agent.ini
[DEFAULT]
interface_driver=neutron.agent.linux.interface.OVSInterfaceDriver
resync_interval=30
enable_isolated_metadata=False
enable_metadata_network=False
debug=False
state_path=/var/lib/neutron
root_helper=sudo neutron-rootwrap /etc/neutron/rootwrap.conf
[agent]
[ovs]
_EOF_
scp ./tmp/dhcp_agent.ini $CONT_MAN_IP:/etc/neutron/dhcp_agent.ini

ssh $CONT_MAN_IP [ ! -f /etc/neutron/metadata_agent.ini.orig ] && cp -v /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.orig
cat << _EOF_ > ./tmp/metadata_agent.ini
[DEFAULT]
metadata_proxy_shared_secret=e52550a9713f45aa
metadata_workers=4
debug=False
nova_metadata_ip=$CONT_MAN_IP
[agent]
[cache]
_EOF_
scp ./tmp/metadata_agent.ini $CONT_MAN_IP:/etc/neutron/metadata_agent.ini

ssh $CONT_MAN_IP [ -h /etc/neutron/plugin.ini ] || ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

cat << _EOF_ > ./tmp/neutron_db_sync
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
_EOF_
ssh $CONT_MAN_IP < ./tmp/neutron_db_sync

cat << _EOF_ > ./tmp/ifcfg-br-ex
PROXY_METHOD=none
BROWSER_ONLY=no
DEFROUTE=yes
ONBOOT=yes
IPADDR=$CONT_EXT_IP
PREFIX=24
DEVICE=br-ex
NAME=br-ex
DEVICETYPE=ovs
OVSBOOTPROTO=none
TYPE=OVSBridge
OVS_EXTRA="set bridge br-ex fail_mode=standalone"
_EOF_
scp ./tmp/ifcfg-br-ex $CONT_MAN_IP:/etc/sysconfig/network-scripts/ifcfg-br-ex

cat << _EOF_ > ./tmp/ifcfg-eth1
DEVICE=eth1
NAME=eth1
DEVICETYPE=ovs
TYPE=OVSPort
OVS_BRIDGE=br-ex
ONBOOT=yes
BOOTPROTO=none
_EOF_
scp ./tmp/ifcfg-eth1 $CONT_MAN_IP:/etc/sysconfig/network-scripts/ifcfg-eth1

ssh $CONT_MAN_IP ifdown eth1; ifdown br-ex; ifup br-ex; ifup eth1

ssh $CONT_MAN_IP systemctl enable neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
ssh $CONT_MAN_IP systemctl restart neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
ssh $CONT_MAN_IP systemctl status neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service

ssh $COMP_MAN_IP yum -y install openstack-neutron-openvswitch

ssh $COMP_MAN_IP [ ! -f /etc/neutron/neutron.conf.orig ] && cp -v /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
cat << _EOF_ > ./tmp/neutron.conf
[DEFAULT]
transport_url = rabbit://openstack:${PASSWORD}@${CONT_MAN_IP}
auth_strategy = keystone
[agent]
[cors]
[database]
[keystone_authtoken]
auth_uri = http://${CONT_MAN_IP}:5000
auth_url = http://${CONT_MAN_IP}:35357
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $PASSWORD
[matchmaker_redis]
[nova]
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[quotas]
[ssl]
_EOF_
scp ./tmp/neutron.conf $COMP_MAN_IP:/etc/neutron/neutron.conf

ssh $COMP_MAN_IP [ ! -f /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig ] && cp -v /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig
cat << _EOF_ > ./tmp/openvswitch_agent.ini.compute
[DEFAULT]
[agent]
tunnel_types=vxlan
vxlan_udp_port=4789
l2_population=False
drop_flows_on_start=False
[network_log]
[ovs]
integration_bridge=br-int
tunnel_bridge=br-tun
local_ip=$COMP_MAN_IP
bridge_mappings=extnet:br-ex
[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
[xenapi]
_EOF_
scp ./tmp/openvswitch_agent.ini.compute $COMP_MAN_IP:/etc/neutron/plugins/ml2/openvswitch_agent.ini

cat << _EOF_ > ./tmp/ifcfg-br-ex.compute
PROXY_METHOD=none
BROWSER_ONLY=no
DEFROUTE=yes
ONBOOT=yes
IPADDR=$COMP_EXT_IP
PREFIX=24
DEVICE=br-ex
NAME=br-ex
DEVICETYPE=ovs
OVSBOOTPROTO=none
TYPE=OVSBridge
OVS_EXTRA="set bridge br-ex fail_mode=standalone"
_EOF_
scp ./tmp/ifcfg-br-ex.compute $COMP_MAN_IP:/etc/sysconfig/network-scripts/ifcfg-br-ex

scp ./tmp/ifcfg-eth1 $COMP_MAN_IP:/etc/sysconfig/network-scripts/ifcfg-eth1

ssh $COMP_MAN_IP ifdown eth1; ifdown br-ex; ifup br-ex; ifup eth1

ssh $COMP_MAN_IP systemctl enable neutron-openvswitch-agent.service
ssh $COMP_MAN_IP systemctl restart neutron-openvswitch-agent.service
ssh $COMP_MAN_IP systemctl status neutron-openvswitch-agent.service
