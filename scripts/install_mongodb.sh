#!/usr/bin/env bash
# Ref : https://www.linode.com/docs/databases/mongodb/install-mongodb-on-ubuntu-16-04

# Make sure only root can run this installer script
if [ "$(id -u)" != "0" ]; then
	echo "You need to be root to run this script" 1>&2
	exit 1
fi

# Make sure this script only run on Ubuntu
if [ ! -f "/etc/lsb-release" ]; then
	echo "This installer only work on Ubuntu server..." 1>&2
	exit 1
fi

function init_mongodb_install() {
    while [[ $INSTALL_MONGODB != "y" && $INSTALL_MONGODB != "n" ]]; do
        read -p "Do you want to Install MongoDB? [y/n]: " -e INSTALL_MONGODB
    done

    if [[ "$INSTALL_MONGODB" == Y* || "$INSTALL_MONGODB" == y* ]]; then
        echo "Installing MongoDB server and MongoDB PHP module..."

        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
        sh -c "echo 'deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse' > /etc/apt/sources.list.d/mongodb-org-4.0.list"
        apt-get update
        apt-get -y install mongodb-org mongodb-org-server

        while [[ $AUTOSTART_MONGODB != "y" && $AUTOSTART_MONGODB != "n" ]]; do
            read -p "Do you want to add MongoDB to systemctl? [y/n]: " -e AUTOSTART_MONGODB
        done

        if [[ "$AUTOSTART_MONGODB" == Y* || "$AUTOSTART_MONGODB" == y* ]]; then
            systemctl restart mongod
            systemctl enable mongodb
            systemctl status mongod
        fi

        echo "Installation completed."
        echo "Please create an administrative user. Example command lines below:";
cat <<- _EOF_
mongo
> use admin
> db.createUser({user: "admin", pwd: "<Enter a secure password>", roles:[{role: "root", db: "admin"}]})
> quit()

mongo -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {capped: false})
> var a = { name : "John Doe",  attributes: { age : 30, address : "123 Main St", phone : 8675309 }}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})
_EOF_
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which mongod) ]]; then
    warning -e "\nMongoDB server already exists. Installation skipped..."
else
    init_mongodb_install "$@"
fi
