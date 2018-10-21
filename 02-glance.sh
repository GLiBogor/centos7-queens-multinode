#!/bin/bash

source os.conf
source admin-openrc
[ -d ./tmp ] || mkdir ./tmp


##### Glance Image Service #####

cat << _EOF_ > ./tmp/glancedb
mysql -u root -p$PASSWORD -e "SHOW DATABASES;" | grep glance > /dev/null 2>&1 && echo "glance database already exists" || mysql -u root -p$PASSWORD -e "CREATE DATABASE glance; GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$PASSWORD'; GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$PASSWORD';"
_EOF_
ssh $CONT_MAN_IP < ./tmp/glancedb

openstack user list | grep glance > /dev/null 2>&1 && echo "glance user already exists" || openstack user create --domain default --password $PASSWORD glance
openstack role add --project service --user glance admin
openstack service list | grep glance > /dev/null 2>&1 && echo "glance service already exists" || openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint list | grep public | grep glance > /dev/null 2>&1 && echo "glance public endpoint already exists" || openstack endpoint create --region RegionOne image public http://${CONT_MAN_IP}:9292
openstack endpoint list | grep internal | grep glance > /dev/null 2>&1 && echo "glance internal endpoint already exists" || openstack endpoint create --region RegionOne image internal http://${CONT_MAN_IP}:9292
openstack endpoint list | grep admin | grep glance > /dev/null 2>&1 && echo "glance admin endpoint already exists" || openstack endpoint create --region RegionOne image admin http://${CONT_MAN_IP}:9292

ssh $CONT_MAN_IP yum -y install openstack-glance

ssh $CONT_MAN_IP [ ! -f /etc/glance/glance-api.conf.orig ] && cp -v /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig
cat << _EOF_ > ./tmp/glance-api.conf
[DEFAULT]
[cors]
[database]
connection = mysql+pymysql://glance:${PASSWORD}@${CONT_MAN_IP}/glance
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
[image_format]
[keystone_authtoken]
auth_uri = http://${CONT_MAN_IP}:5000
auth_url = http://${CONT_MAN_IP}:5000
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $PASSWORD
[matchmaker_redis]
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[paste_deploy]
flavor = keystone
[profiler]
[store_type_location_strategy]
[task]
[taskflow_executor]
_EOF_
scp ./tmp/glance-api.conf $CONT_MAN_IP:/etc/glance/glance-api.conf

ssh $CONT_MAN_IP [ ! -f /etc/glance/glance-registry.conf.orig ] && cp -v /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.orig
cat << _EOF_ > ./tmp/glance-registry.conf
[DEFAULT]
[database]
connection = mysql+pymysql://glance:${PASSWORD}@${CONT_MAN_IP}/glance
[keystone_authtoken]
auth_uri = http://${CONT_MAN_IP}:5000
auth_url = http://${CONT_MAN_IP}:5000
memcached_servers = ${CONT_MAN_IP}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $PASSWORD
[matchmaker_redis]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_policy]
[paste_deploy]
flavor = keystone
[profiler]
_EOF_
scp ./tmp/glance-registry.conf $CONT_MAN_IP:/etc/glance/glance-registry.conf

cat << _EOF_ > ./tmp/glance_db_sync
su -s /bin/sh -c "glance-manage db_sync" glance
_EOF_
ssh $CONT_MAN_IP < ./tmp/glance_db_sync

ssh $CONT_MAN_IP systemctl enable openstack-glance-api.service openstack-glance-registry.service
ssh $CONT_MAN_IP systemctl restart openstack-glance-api.service openstack-glance-registry.service
ssh $CONT_MAN_IP systemctl status openstack-glance-api.service openstack-glance-registry.service

yum -y install wget
wget -c http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -P ./tmp/
openstack image list | grep cirros-0.4.0-x86_64-disk.img || openstack image create "cirros-0.4.0-x86_64-disk.img" --file ./tmp/cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --public
openstack image list
