#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp


##### Nova Compute Service #####

cat << _EOF_ > ./tmp/novadb
mysql -u root -p$PASSWORD -e "SHOW DATABASES;" | grep nova > /dev/null 2>&1 && echo "nova database already exists" || mysql -u root -p$PASSWORD -e "CREATE DATABASE nova; GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
mysql -u root -p$PASSWORD -e "SHOW DATABASES;" | grep nova_api > /dev/null 2>&1 && echo "nova_api database already exists" || mysql -u root -p$PASSWORD -e "CREATE DATABASE nova_api; GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
mysql -u root -p$PASSWORD -e "SHOW DATABASES;" | grep nova_cell0 > /dev/null 2>&1 && echo "nova_cell0 database already exists" || mysql -u root -p$PASSWORD -e "CREATE DATABASE nova_cell0; GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CONT_MAN_IP < ./tmp/novadb

openstack user list | grep nova > /dev/null 2>&1 && echo "nova user already exists" || openstack user create --domain default --password $PASSWORD nova
openstack role add --project service --user nova admin
openstack service list | grep nova > /dev/null 2>&1 && echo "nova service already exists" || openstack service create --name nova --description "OpenStack Compute service" compute
openstack endpoint list | grep public | grep nova > /dev/null 2>&1 && echo "nova public endpoint already exists" || openstack endpoint create --region RegionOne compute public http://${CONT_MAN_IP}:8774/v2.1
openstack endpoint list | grep internal | grep nova > /dev/null 2>&1 && echo "nova internal endpoint already exists" || openstack endpoint create --region RegionOne compute internal http://${CONT_MAN_IP}:8774/v2.1
openstack endpoint list | grep admin | grep nova > /dev/null 2>&1 && echo "nova admin endpoint already exists" || openstack endpoint create --region RegionOne compute admin http://${CONT_MAN_IP}:8774/v2.1
openstack user list | grep placement > /dev/null 2>&1 && echo "placement user already exists" || openstack user create --domain default --password $PASSWORD placement
openstack role add --project service --user placement admin
openstack service list | grep placement > /dev/null 2>&1 && echo "placement service already exists" || openstack service create --name placement --description "Placement API" placement
openstack endpoint list | grep public | grep placement > /dev/null 2>&1 && echo "placement public endpoint already exists" || openstack endpoint create --region RegionOne placement public http://${CONT_MAN_IP}:8778
openstack endpoint list | grep internal | grep placement > /dev/null 2>&1 && echo "placement internal endpoint already exists" || openstack endpoint create --region RegionOne placement internal http://${CONT_MAN_IP}:8778
openstack endpoint list | grep admin | grep placement > /dev/null 2>&1 && echo "placement admin endpoint already exists" || openstack endpoint create --region RegionOne placement admin http://${CONT_MAN_IP}:8778

ssh $CONT_MAN_IP yum -y install openstack-nova-api openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-placement-api

ssh $CONT_MAN_IP [ ! -f /etc/nova/nova.conf.orig ] && cp -v /etc/nova/nova.conf /etc/nova/nova.conf.orig
cat << _EOF_ > ./tmp/nova.conf
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:${PASSWORD}@${CONT_MAN_IP}
my_ip = $CONT_MAN_IP
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:${PASSWORD}@${CONT_MAN_IP}/nova_api
[barbican]
[cache]
[cells]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[crypto]
[database]
connection = mysql+pymysql://nova:${PASSWORD}@${CONT_MAN_IP}/nova
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://${CONT_MAN_IP}:9292
[guestfs]
[healthcheck]
[hyperv]
[ironic]
[key_manager]
[keystone]
[keystone_authtoken]
auth_url = http://${CONT_MAN_IP}:5000/v3
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = $PASSWORD
[libvirt]
[matchmaker_redis]
[metrics]
[mks]
[neutron]
[notifications]
[osapi_v21]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[pci]
[placement]
os_region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://${CONT_MAN_IP}:5000/v3
username = placement
password = $PASSWORD
[quota]
[rdp]
[remote_debug]
[scheduler]
discover_hosts_in_cells_interval = 300
[serial_console]
[service_user]
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]
[vnc]
enabled = true
server_listen = $CONT_MAN_IP
server_proxyclient_address = $CONT_MAN_IP
[workarounds]
[wsgi]
[xenserver]
[xvp]
_EOF_
scp ./tmp/nova.conf $CONT_MAN_IP:/etc/nova/nova.conf

ssh $CONT_MAN_IP [ ! -f /etc/httpd/conf.d/00-nova-placement-api.conf.orig ] && cp -v /etc/httpd/conf.d/00-nova-placement-api.conf /etc/httpd/conf.d/00-nova-placement-api.conf.orig
cat << _EOF_ > ./tmp/00-nova-placement-api.conf
Listen 8778

<VirtualHost *:8778>
  WSGIProcessGroup nova-placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
  WSGIDaemonProcess nova-placement-api processes=3 threads=1 user=nova group=nova
  WSGIScriptAlias / /usr/bin/nova-placement-api
  <IfVersion >= 2.4>
    ErrorLogFormat "%M"
  </IfVersion>
  ErrorLog /var/log/nova/nova-placement-api.log
  #SSLEngine On
  #SSLCertificateFile ...
  #SSLCertificateKeyFile ...
</VirtualHost>

Alias /nova-placement-api /usr/bin/nova-placement-api
<Location /nova-placement-api>
  SetHandler wsgi-script
  Options +ExecCGI
  WSGIProcessGroup nova-placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
</Location>

<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>
_EOF_
scp ./tmp/00-nova-placement-api.conf $CONT_MAN_IP:/etc/httpd/conf.d/00-nova-placement-api.conf

ssh $CONT_MAN_IP systemctl restart httpd.service
ssh $CONT_MAN_IP systemctl status httpd.service

cat << _EOF_ > ./tmp/nova_db_sync
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
_EOF_
ssh $CONT_MAN_IP < ./tmp/nova_db_sync

nova-manage cell_v2 list_cells

ssh $CONT_MAN_IP systemctl enable openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
ssh $CONT_MAN_IP systemctl restart openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
ssh $CONT_MAN_IP systemctl status openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service

ssh $COMP_MAN_IP yum -y install openstack-nova-compute

ssh $COMP_MAN_IP [ ! -f /etc/nova/nova.conf.orig ] && cp -v /etc/nova/nova.conf /etc/nova/nova.conf.orig
cat << _EOF_ > ./tmp/nova.conf.compute
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:${PASSWORD}@${CONT_MAN_IP}
my_ip = $COMP_MAN_IP
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver
[api]
auth_strategy = keystone
[api_database]
[barbican]
[cache]
[cells]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[crypto]
[database]
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://${CONT_MAN_IP}:9292
[guestfs]
[healthcheck]
[hyperv]
[ironic]
[key_manager]
[keystone]
[keystone_authtoken]
auth_url = http://${CONT_MAN_IP}:5000/v3
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = $PASSWORD
[libvirt]
virt_type = kvm
[matchmaker_redis]
[metrics]
[mks]
[neutron]
[notifications]
[osapi_v21]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[pci]
[placement]
os_region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://${CONT_MAN_IP}:5000/v3
username = placement
password = $PASSWORD
[quota]
[rdp]
[remote_debug]
[scheduler]
[serial_console]
[service_user]
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]
[vnc]
enabled = True
server_listen = 0.0.0.0
server_proxyclient_address = $COMP_MAN_IP
novncproxy_base_url = http://${CONT_MAN_IP}:6080/vnc_auto.html
[workarounds]
[wsgi]
[xenserver]
[xvp]
_EOF_
scp ./tmp/nova.conf.compute $COMP_MAN_IP:/etc/nova/nova.conf

ssh $COMP_MAN_IP systemctl enable libvirtd.service openstack-nova-compute.service
ssh $COMP_MAN_IP systemctl restart libvirtd.service openstack-nova-compute.service
ssh $COMP_MAN_IP systemctl status libvirtd.service openstack-nova-compute.service

openstack compute service list --service nova-compute
