#!/bin/bash

source os.conf
[ -d ./tmp ] || mkdir ./tmp


##### Host Maping #####

cat << _EOF_ > ./tmp/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$CONT_MAN_IP $CONT_HOSTNAME
$COMP_MAN_IP $COMP_HOSTNAME
_EOF_

scp ./tmp/hosts $CONT_MAN_IP:/etc/hosts
scp ./tmp/hosts $COMP_MAN_IP:/etc/hosts


##### Firewall Service #####

ssh $CONT_MAN_IP systemctl stop firewalld.service
ssh $CONT_MAN_IP systemctl disable firewalld.service
ssh $CONT_MAN_IP systemctl status firewalld.service
ssh $COMP_MAN_IP systemctl stop firewalld.service
ssh $COMP_MAN_IP systemctl disable firewalld.service
ssh $COMP_MAN_IP systemctl status firewalld.service


##### NTP Service #####

ssh $CONT_MAN_IP yum -y install chrony
ssh $CONT_MAN_IP systemctl enable chronyd.service
ssh $CONT_MAN_IP systemctl restart chronyd.service
ssh $CONT_MAN_IP systemctl status chronyd.service
ssh $CONT_MAN_IP chronyc sources
ssh $COMP_MAN_IP yum -y install chrony
ssh $COMP_MAN_IP systemctl enable chronyd.service
ssh $COMP_MAN_IP systemctl restart chronyd.service
ssh $COMP_MAN_IP systemctl status chronyd.service
ssh $COMP_MAN_IP chronyc sources


##### OpenStack Packages #####

ssh $CONT_MAN_IP yum -y install centos-release-openstack-queens
ssh $CONT_MAN_IP yum -y upgrade
ssh $CONT_MAN_IP yum -y install python-openstackclient openstack-selinux
ssh $COMP_MAN_IP yum -y install centos-release-openstack-queens
ssh $COMP_MAN_IP yum -y upgrade
ssh $COMP_MAN_IP yum -y install python-openstackclient openstack-selinux


##### MariaDB Service #####

ssh $CONT_MAN_IP yum -y install mariadb mariadb-server python2-PyMySQL

if ssh $CONT_MAN_IP [ ! -f /etc/my.cnf.d/openstack.cnf ]
  then
cat << _EOF_ > ./tmp/openstack.cnf
[mysqld]
bind-address = $CONT_MAN_IP
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
_EOF_
  scp ./tmp/openstack.cnf $CONT_MAN_IP:/etc/my.cnf.d/openstack.cnf
  ssh $CONT_MAN_IP systemctl enable mariadb.service
  ssh $CONT_MAN_IP systemctl restart mariadb.service
  ssh $CONT_MAN_IP systemctl status mariadb.service
cat << _EOF_ > ./tmp/mysql_secure_installation
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$PASSWORD') WHERE User='root';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
mysql -e "FLUSH PRIVILEGES;"
_EOF_
  ssh $CONT_MAN_IP < ./tmp/mysql_secure_installation
fi


##### RabbitMQ Service #####

ssh $CONT_MAN_IP yum -y install rabbitmq-server
ssh $CONT_MAN_IP systemctl enable rabbitmq-server.service
ssh $CONT_MAN_IP systemctl restart rabbitmq-server.service
ssh $CONT_MAN_IP systemctl status rabbitmq-server.service
ssh $CONT_MAN_IP rabbitmqctl add_user openstack $PASSWORD
ssh $CONT_MAN_IP rabbitmqctl set_permissions openstack \".*\" \".*\" \".*\"


##### Memcached Service #####

ssh $CONT_MAN_IP yum -y install memcached python-memcached
cat << _EOF_ > ./tmp/etc_sysconfig_memcached
sed -i 's/OPTIONS="-l 127.0.0.1,::1"/OPTIONS="-l 127.0.0.1,::1,$CONT_MAN_IP"/g' /etc/sysconfig/memcached
_EOF_
ssh $CONT_MAN_IP < ./tmp/etc_sysconfig_memcached
ssh $CONT_MAN_IP systemctl enable memcached.service
ssh $CONT_MAN_IP systemctl restart memcached.service
ssh $CONT_MAN_IP systemctl status memcached.service


##### Etcd Service #####

ssh $CONT_MAN_IP yum -y install etcd
ssh $CONT_MAN_IP [ ! -f /etc/etcd/etcd.conf.orig ] && cp -v /etc/etcd/etcd.conf /etc/etcd/etcd.conf.orig
cat << _EOF_ > ./tmp/etcd.conf
#[Member]
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://${CONT_MAN_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${CONT_MAN_IP}:2379"
ETCD_NAME="`ssh $CONT_MAN_IP hostname`"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${CONT_MAN_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${CONT_MAN_IP}:2379"
ETCD_INITIAL_CLUSTER="`ssh $CONT_MAN_IP hostname`=http://${CONT_MAN_IP}:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER_STATE="new"
_EOF_
scp ./tmp/etcd.conf $CONT_MAN_IP:/etc/etcd/etcd.conf
ssh $CONT_MAN_IP systemctl enable etcd
ssh $CONT_MAN_IP systemctl restart etcd
ssh $CONT_MAN_IP systemctl status etcd
