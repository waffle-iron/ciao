#!/bin/bash

ciao_host=$(hostname)
ciao_bin="$HOME/local"
ciao_cert="$ciao_bin""/cert-Scheduler-""$ciao_host"".pem"

ciao_email="ciao-devel@lists.clearlinux.org"
ciao_org="Intel"
ciao_src="$GOPATH/src/github.com/01org/ciao"
ciao_scripts="$GOPATH/src/github.com/01org/ciao/testutil/singlevm"
ciao_env="$ciao_bin/demo.sh"
ciao_ctl_log="/var/lib/ciao/logs/controller/ciao-controller.ERROR"
ciao_cnci_image="clear-8260-ciao-networking.img"


#Stop any running agents
sudo killall ciao-scheduler
sudo killall ciao-controller
sudo killall ciao-launcher
sleep 5


#Create a directory where all the certificates, binaries and other
#dependencies are placed
mkdir "$ciao_bin"
cd "$ciao_bin"

#Cleanup any old artifcats
rm -f "$ciao_bin"/*.pem
sudo rm -f "$ciao_bin"/ciao-controller.db-shm 
sudo rm -f "$ciao_bin"/ciao-controller.db-wal 
sudo rm -f "$ciao_bin"/ciao-controller.db
sudo rm -f /tmp/ciao-controller-stats.db
rm -rf "$ciao_bin"/tables
rm -rf "$ciao_bin"/workloads


#Generate Certificates
$GOPATH/bin/ciao-cert -server -role scheduler -email="$ciao_email" -organization="$ciao_org" -host="$ciao_host" -verify 

$GOPATH/bin/ciao-cert -role cnciagent -server-cert "$ciao_cert" -email="$ciao_email" -organization="ciao_org" -host="$ciao_host" -verify 

$GOPATH/bin/ciao-cert -role controller -server-cert "$ciao_cert" -email="$ciao_email" -organization="$ciao_org" -host="$ciao_host" -verify 

$GOPATH/bin/ciao-cert -role agent,netagent -server-cert "$ciao_cert" -email="ciao_email" -organization="ciao_org" -host="$ciao_host" -verify

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout controller_key.pem -out controller_cert.pem -subj "/C=US/ST=CA/L=Santa Clara/O=ciao/CN=ciao.example.com"

#Build ciao
cd "$ciao_src"
go install -v --tags 'debug' ./...
cd "$ciao_bin"

#Copy the configuration
cp -a "$ciao_src"/ciao-controller/tables "$ciao_bin"
cp -a "$ciao_src"/ciao-controller/workloads "$ciao_bin"

#Copy the launch scripts
cp "$ciao_scripts"/run_scheduler.sh "$ciao_bin"
cp "$ciao_scripts"/run_controller.sh "$ciao_bin"
cp "$ciao_scripts"/run_launcher.sh "$ciao_bin"


#Generate the CNCI VM
cd "$ciao_bin"
"$GOPATH"/src/github.com/01org/ciao/networking/ciao-cnci-agent/scripts/generate_cnci_cloud_image.sh -c "$ciao_bin" -i "$ciao_cnci_image" -d
qemu-img convert -f raw -O qcow2 "$ciao_cnci_image" "$ciao_cnci_image".qcow
sudo cp "$ciao_cnci_image".qcow /var/lib/ciao/images
cd /var/lib/ciao/images
sudo ln -sf "$ciao_cnci_image".qcow 4e16e743-265a-4bf2-9fd1-57ada0b28904

#Kick off the agents
cd "$ciao_bin"
"$ciao_bin"/run_scheduler.sh  &> /dev/null
"$ciao_bin"/run_launcher.sh &> /dev/null
"$ciao_bin"/run_controller.sh &> /dev/null

echo "export CIAO_CONTROLLER=""$ciao_host" > "$ciao_env"
echo "export CIAO_USERNAME=admin" >> "$ciao_env"
echo "export CIAO_PASSWORD=giveciaoatry" >> "$ciao_env"
sleep 5
cat "$ciao_ctl_log"
identity=`grep CIAO_IDENTITY $ciao_ctl_log | sed 's/^.*export/export/'`
echo "$identity" >> "$ciao_env"
export CIAO_CONTROLLER="$ciao_host"
export CIAO_USERNAME=admin
export CIAO_PASSWORD=giveciaoatry
eval "$identity"
ciao-cli --list-workloads
ciao-cli --launch-instances --workload=e35ed972-c46c-4aad-a1e7-ef103ae079a2 --instances=2
ciao-cli --launch-instances --workload=ab68111c-03a6-11e6-87de-001320fb6e31 --instances=2
ciao-cli --list-instances
sleep 30
ciao-cli --list-instances

#Check docker networking
docker_id=`sudo docker ps -q | head -1`
sudo docker logs $docker_id

#Check SSH connectivity
ssh_ip=`ciao-cli --list-instances |  grep "SSH IP:" | sed 's/^.*SSH IP: //' | head -1`
head -1 < /dev/tcp/"$ssh_ip"/33002
