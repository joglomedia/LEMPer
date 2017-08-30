#!/usr/bin/env bash
# Ref : https://www.linode.com/docs/databases/mongodb/install-mongodb-on-ubuntu-16-04

# Make sure only root can run this installer script
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root..." 1>&2
	exit 1
fi

# Make sure this script only run on Ubuntu install
if [ ! -f "/etc/lsb-release" ]; then
	echo "This installer only work on Ubuntu server..." 1>&2
	exit 1
fi

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 58712A2291FA4AD5
sh -c "echo 'deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.5 multiverse' > /etc/apt/sources.list.d/mongodb-org-3.5.list"
apt-get update
apt-get install -y mongodb-org

#mongo
#use admin
#db.createUser({user: "admin", pwd: "admin1234", roles:[{role: "root", db: "admin"}]})
#quit()

#mongo -u admin -p --authenticationDatabase user-data
#use exampledb
#db.createCollection("exampleCollection", {capped: false})
#var a = { name : "John Doe",  attributes: { age : 30, address : "123 Main St", phone : 8675309 }}
#db.exampleCollection.insert(a)
#WriteResult({ "nInserted" : 1 })
#db.exampleCollection.find()
#db.exampleCollection.find({"name" : "John Doe"})
