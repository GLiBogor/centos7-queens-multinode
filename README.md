# centos7-queens-multinode

This repo contains bash scripts for manually install services of OpenStack Queens by using packages on RHEL/CentOS 7 through the RDO repository. The services in this installation include Keystone Identity, Glance Image, Nova Compute, Neutron Networking with OpenvSwitch and Horizon Dashboard. The architecture in this installation intended to assist new users of OpenStack to understand basic installation, configuration and operation of OpenStack core services. The architecture is not recommended for production environment. The architecture is using 2 VirtualBox nodes for controller and compute.


__Main Reference:__
https://docs.openstack.org/install-guide/openstack-services.html#minimal-deployment-for-queens

__Minimum requirements:__
- Desktop/laptop with 4 cores 64bit processor and 16 GB RAM.
- 2 VirtualBox guests of RHEL/CentOS 7 minimal installation. Node controller: 4 core CPU, 8 GB RAM, 20 GB HDD. Node compute: 4 core CPU, 4 GB RAM, 20 GB HDD

__Topology:__
![alt tag](https://raw.githubusercontent.com/GLiBogor/centos7-queens-multinode/master/topology.png)

__Installation:__
1. Adjust the IP addresses and the hostname in the os.conf file.
2. Set root passwordless SSH to each node
3. Execute the bash scripts in number order starting with the lowest to the greater number (00-env.sh to 05-horizon.sh)
