#!/bin/bash

##
## This script install:
##      - Java + Jetty + Tomcat
##      - Nginx with SSL force redirect support
##      - MongoDB with Auth
##      - Apply network security rules
##

BASE_DIR=$(dirname `pwd`/a)

## vars mongo
MONGO_ADMIN_PWD="Ncmd93idjJedsR2"
MONGO_DB="ZupDB"
MONGO_USER="zupuser"
MONGO_PASS="JIJxcnsd832dnJda"

## Java Version (1.6, 1.7 or 1.8)
JAVA_VERSION="1.8"

## Jetty Version
JETTY_MAJOR_VERSION="9"
JETTY_VERSION="9.3.6.v20151106"

## Tomcat Version
TOMCAT_MAJOR_VERSION="9"
TOMCAT_VERSION="9.0.0.M1"

##
## Install Pre Reqs
##
install_prereqs() {
    sudo yum install -y tar bzip2 gzip openssl
}

##
## Install Java / jetty / tomcat
##
install_java() {
    ## check and install java
    rpm -qa | grep java-$JAVA_VERSION.0-openjdk
    if [ $? -ne 0 ]; then
        sudo yum install -y java-$JAVA_VERSION.0-openjdk
    fi

    ## check and install jetty
    if [ ! -d "/opt/jetty-distribution-$JETTY_VERSION" ]; then
        URL="http://download.eclipse.org/jetty/stable-$JETTY_MAJOR_VERSION/dist/jetty-distribution-$JETTY_VERSION.tar.gz"
        curl -O $URL
        if [ $? -ne 0 ]; then
            echo "Error download $URL" 
            exit 1; 
        fi

        sudo tar xf jetty-distribution-$JETTY_VERSION.tar.gz
        sudo mv jetty-distribution-$JETTY_VERSION /opt
        sudo ln -s /opt/jetty-distribution-$JETTY_VERSION /opt/jetty

        sudo adduser -r -m jetty
        sudo chown -R jetty:jetty /opt/jetty-distribution-$JETTY_VERSION
        sudo ln -s /opt/jetty-distribution-$JETTY_VERSION/bin/jetty.sh /etc/init.d/jetty
        sudo chkconfig --add jetty
        sudo chkconfig jetty off ## not run on boot

        sudo cp $BASE_DIR/jetty/jetty /etc/default/jetty
    fi

    ## check and install Tomcat
    if [ ! -d "/opt/apache-tomcat-$TOMCAT_VERSION" ]; then
        URL="http://mirror.nbtelecom.com.br/apache/tomcat/tomcat-$TOMCAT_MAJOR_VERSION/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
        curl -O $URL
        if [ $? -ne 0 ]; then
            echo "Error download $URL" 
            exit 1; 
        fi

        sudo tar xf apache-tomcat-$TOMCAT_VERSION.tar.gz
        sudo mv apache-tomcat-$TOMCAT_VERSION /opt
        sudo ln -s /opt/apache-tomcat-$TOMCAT_VERSION /opt/tomcat
    fi
}

##
## Install Nginx
##
install_nginx() {
    ## check nginx installed
    rpm -qa | grep nginx
    if [ $? -eq 0 ]; then
        echo "Install Nginx ...... OK"
        return
    fi

    ## add nginx repo
    echo -e "[nginx]\nname=nginx repo\nbaseurl=http://nginx.org/packages/centos/6/\$basearch/\ngpgcheck=0\nenabled=1" > /etc/yum.repos.d/nginx.repo
    sudo yum install -y nginx

    ## generate ssl certificate
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $BASE_DIR/nginx/mydomain.com.key \
            -out $BASE_DIR/nginx/mydomain.com.crt

    ## prepare nginx config
    sudo rm -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/example_ssl.conf
    sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx_bkp.conf
    sudo cp $BASE_DIR/nginx/nginx.conf /etc/nginx/
    sudo cp $BASE_DIR/nginx/mydomain.conf /etc/nginx/conf.d/_mydomain.conf
    sudo mkdir /etc/nginx/ssl
    sudo cp $BASE_DIR/nginx/mydomain.com.key $BASE_DIR/nginx/mydomain.com.crt /etc/nginx/ssl
    sudo chown nginx:nginx -R /etc/nginx/ssl
    sudo chmod 600 /etc/nginx/ssl/mydomain.com.key /etc/nginx/ssl/mydomain.com.crt

    ## service start
    sudo chkconfig nginx on
    sudo service nginx start

    ## disable selinux
    sudo echo 0 > /selinux/enforce
}

##
## Install MongoDB
##
install_mongodb() {
    ## check mongodb installed
    rpm -qa | grep mongodb-org-server
    if [ $? -eq 0 ]; then
        echo "Install MongoDB ...... OK"
        return
    fi

    ## add mongodb repo
    echo -e "[mongodb-org-3.0]\nname=MongoDB Repository\nbaseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/3.0/x86_64/\ngpgcheck=0\nenabled=1" > /etc/yum.repos.d/mongodb-org-3.0.repo
    sudo yum install -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-tools

    ## enable authentication
    echo -e "\nsecurity:\n  authorization: enabled\n" >> /etc/mongod.conf

    ## service start
    sudo chkconfig mongod on
    sudo service mongod start

    ## defined admin password
    mongo admin --eval "db.createUser({user: 'admin', pwd: '$MONGO_ADMIN_PWD', roles:[{role:'root',db:'admin'}]});"

    ## defined app user and password
    mongo -u admin -p $MONGO_ADMIN_PWD $MONGO_DB \
            --authenticationDatabase admin \
            --eval "db.createUser({user: '$MONGO_USER', pwd: '$MONGO_PASS', roles:[{role:'readWrite',db:'$MONGO_DB'}]});"
}



##
## Apply Network Rules
##
apply_network_rules () {

    echo -n "Apply network rules ...... "

sudo cat << EOF > /etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [18:2872]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
-A INPUT -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j DROP
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG FIN,SYN,RST,PSH,ACK,URG -j DROP
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
COMMIT
EOF

    sudo service iptables restart

    echo " OK"

    if [ $? -ne 0 ]; then
        echo "Restart iptables service unsuccesfully"
    fi
}

##
## Instructions post install
##
echo_finish() {
    echo "\n\n******* INSTRUCTIONS *******"
    echo
    echo "=== MongoDB ==="
    echo "user: $MONGO_USER"
    echo "pass: $MONGO_PASS"
    echo "database: $MONGO_DB"
    echo
    echo "== Nginx =="
    echo "Force redirect request http to https"
    echo
    echo "== Jetty =="
    echo "Version: $JETTY_VERSION"
    echo "Sevice /etc/init.d/jetty is stoped by default"
    echo "Dir installation is /opt/jetty"
    echo
    echo "== Tomcat =="
    echo "Version: $TOMCAT_VERSION"
    echo "Service /opt/tomcat/bin/catalina.sh run"
    echo "Dir installation is /opt/tomcat"
    echo
    echo
    echo "SUCCESS! This installation is finished."
    echo
}

## pipeline
apply_network_rules
install_prereqs
install_java
install_nginx
install_mongodb
echo_finish

exit 0
