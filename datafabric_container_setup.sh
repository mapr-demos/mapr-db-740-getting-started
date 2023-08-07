#!/bin/bash
#set -x
IMAGE="maprtech/edf-seed-container:latest"
INTERFACE="en0"

usage()
{
   echo "This script will take of deploying edf on seed node."
   echo
   echo "Syntax: ./datafabric_container_setup.sh [-i|--image] [-p|--publicipv4dns]"
   echo "options:"
   echo "-i|--image this is optional,By defaul it will pull image having latest tag, 
         we can also provide image which has custom tag example:maprtech/edf-seed-container:7.3.0_9.1.1"
   echo "-p|--publicipv4dns is the public IPv4 DNS and needed for cloud deployed seed nodes. Note that both inbound and outbound trafic on port 8443              
         needs to be enabled on the cloud instance. Otherwise, the Data Fabric UI cannot be acessible"
   echo
}

#checking if required memory is present or not
os_vers=`uname -s` > /dev/null 2>&1
if [ "$os_vers" == "Darwin" ]; then
     memory_avilable_mac=$(system_profiler SPHardwareDataType | grep "Memory" | awk '{print $2}')  &>/dev/null
       if  [ $memory_avilable_mac -lt 32 ] ; then
           echo "RAM needed to run seed node is 32 GB or more on MACBook."
           echo "Looks like sufficent RAM is not avilable on this machine"
           echo "Please try to spin up seed node on a machine which has sufficent memory"
           exit
       fi
fi
if [ "$os_vers" == "Linux" ]; then
       memory_avilable_linux=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')  &>/dev/null 
         if  [ $memory_avilable_linux -lt 25165824 ]; then
             echo "RAM needed to run seed node is 24 GB or more on linux nodes."
             echo "Looks like sufficent RAM is not avilable on this machine"
             echo "Please try to spin up seed node on a machine which has sufficent memory"
             exit
         fi
fi

#check if docker is installed and running
docker info > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "Docker is not installed/not-running on the system.Please install/start docker to proceed forward"
    echo "Reference link to install : https://docs.docker.com/engine/install/"
    exit
fi

#check connectivity to docker hub
docker run hello-world  > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "Docker is installed on the system but we are not able to pull images from docker hub"
    echo "Please check internet connectivity or if the machine is behind a proxy"
    echo "If the machine is running behind a proxy please update /etc/environment with appropriate  proxy settings accordingly"
    exit
fi

#check if ports used by datafabric is already used by some other process
docker ps -a | grep edf-seed-container > /dev/null 2>&1
if [ $? != 0 ]; then
   seednodeports='7221 5660 5692 5724 5756 8443 8188 7222 5181'
   pc=0
   for port in $seednodeports
   do
    result=`lsof -i:${port} | grep LISTEN`
    retval=$?
    if [ $retval -eq 0 ]; then
      echo "${port} port is being used"
      pc=1
    fi
  done
if [ $pc -eq 1 ]; then
   echo "it seems to be that some existing application using the required ports so please make sure to clean them up before attempting again"
   exit 1
fi
fi


while [ $# -gt 0 ]
do
  case "$1" in
  -i|--image) shift;
  IMAGE=$1;;
  -p|--publicipv4dns) shift;
  PUBLICIPV4DNS=$1;;
  *) shift;
   usage
   exit;;
   esac
   shift
done

which ipconfig &>/dev/null
if [ $? -eq 0 ]; then
  INTERFACE=$(route -n get default | grep interface | awk '{print $2}')
  IP=$(ipconfig getifaddr $INTERFACE)
else
  INTERFACE=$(ip route | grep default | awk '{print $5}')
  IP=$(ip addr show $INTERFACE | grep -w inet | awk '{ print $2}' | cut -d "/" -f1)
fi
hostName="${hostName:-"edf-installer.hpe.com"}"
clusterName=$(echo ${hostName} | cut -d '.' -f 1)

runMaprImage() {
    echo "Please enter the local sudo password for $(whoami)"
        sudo rm -rf /tmp/maprdemo
        sudo mkdir -p /tmp/maprdemo/hive /tmp/maprdemo/zkdata /tmp/maprdemo/pid /tmp/maprdemo/logs /tmp/maprdemo/nfs
        sudo chmod -R 777 /tmp/maprdemo/hive /tmp/maprdemo/zkdata /tmp/maprdemo/pid /tmp/maprdemo/logs /tmp/maprdemo/nfs

        PORTS='-p 9998:9998 -p 8042:8042 -p 8888:8888 -p 8088:8088 -p 9997:9997 -p 10001:10001 -p 8190:8190 -p 8243:8243 -p 2222:22 -p 4040:4040 -p 7221:7221 -p 8090:8090 -p 5660:5660 -p 8443:8443 -p 19888:19888 -p 50060:50060 -p 18080:18080 -p 8032:8032 -p 14000:14000 -p 19890:19890 -p 10000:10000 -p 11443:11443 -p 12000:12000 -p 8081:8081 -p 8002:8002 -p 8080:8080 -p 31010:31010 -p 8044:8044 -p 8047:8047 -p 11000:11000 -p 2049:2049 -p 8188:8188 -p 7077:7077 -p 7222:7222 -p 5181:5181 -p 5661:5661 -p 5692:5692 -p 5724:5724 -p 5756:5756 -p 10020:10020 -p 50000-50050:50000-50050 -p 9001:9001 -p 5693:5693 -p 9002:9002 -p 31011:31011'
        #export MAPR_EXTERNAL="0.0.0.0"
  #incase non-mac ipconfig command would not be found
  which ipconfig &>/dev/null
  if [ $? -eq 0 ]; then
    export MAPR_EXTERNAL=$(ipconfig getifaddr $INTERFACE)
  else
    export MAPR_EXTERNAL=$(ip addr show $INTERFACE | grep -w inet | awk '{ print $2}' | cut -d "/" -f1)
  fi

 
  if [ "${PUBLICIPV4DNS}" == "" ]; then
	echo ""
  else
    export PUBLICIPV4DNS="${PUBLICIPV4DNS}"
  fi

        docker pull ${IMAGE}; 
        docker run -d --privileged -v /tmp/maprdemo/zkdata:/opt/mapr/zkdata -v /tmp/maprdemo/pid:/opt/mapr/pid  -v /tmp/maprdemo/logs:/opt/mapr/logs  -v /tmp/maprdemo/nfs:/mapr $PORTS -e MAPR_EXTERNAL -e clusterName -e isSecure --hostname ${clusterName} ${IMAGE} > /dev/null 2>&1

   # Check if docker container is started wihtout any issue
   sleep 5 # wait for docker container to start

    CID=$(docker ps -a | grep edf-seed-container | awk '{ print $1 }' )
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CID 2> /dev/null)
    ERROR=$(docker inspect --format="{{.State.Error}}" $CID 2> /dev/null)

    if [ "$RUNNING" == "true" -a "$ERROR" == "" ]
    then
            echo "Developer Sandbox Container $CID is running.."
    else
            echo "Failed to start Developer Sandbox Container $CID. Error: $ERROR"
            exit
    fi
}

docker ps -a | grep edf-seed-container > /dev/null 2>&1
if [ $? -ne 0 ]
then
        STATUS='NOTRUNNING'
else
        echo "MapR sandbox container is already running."
        echo "1. Kill the earlier run and start a fresh instance"
        echo "2. Reconfigure the client and the running container for any network changes"
        echo -n "Please enter choice 1 or 2 : "
        read ANS
        if [ "$ANS" == "1" ]
        then
                CID=$(docker ps -a | grep edf-seed-container | awk '{ print $1 }' )
                docker stop $CID > /dev/null 2>&1
                docker rm -f $CID > /dev/null 2>&1
                STATUS='NOTRUNNING'
        else
                STATUS='RUNNING'
        fi
fi

if [ "$STATUS" == "RUNNING" ]
then
        # There is an instance of dev-sandbox-container. Check if it is running or not.
        CID=$(docker ps -a | grep edf-seed-container | awk '{ print $1 }' )
        RUNNING=$(docker inspect --format="{{.State.Running}}" $CID 2> /dev/null)
        if [ "$RUNNING" == "true" ]
        then
                # Container is running there.
                # Change the IP in /etc/hosts and reconfigure client for the IP Change
                # Change the server side settings and restart warden
                grep ${hostName} /etc/hosts | grep ${IP} > /dev/null 2>&1
                if [ $? -ne 0 ]
                then
                        echo "Please enter the local sudo password for $(whoami)"
                        sudo sed -i '' '/'${hostName}'/d' /etc/hosts &>/dev/null
                        sudo  sh -c "echo  \"${IP}      ${hostName}  ${clusterName}\" >> /etc/hosts"
                        sudo sed -i '' '/'${hostName}'/d' /opt/mapr/conf/mapr-clusters.conf &>/dev/null
            		sudo /opt/mapr/server/configure.sh -c -C ${hostName}  -N ${clusterName} > /dev/null 2>&1
                        # Change the external IP in the container
                        echo "Please enter the root password of the container 'mapr' "
                        ssh root@localhost -p 2222 " sed -i \"s/MAPR_EXTERNAL=.*/MAPR_EXTERNAL=${IP}/\" /opt/mapr/conf/env.sh "
                        echo "Please enter the root password of the container 'mapr' "
                        ssh root@localhost -p 2222 "service mapr-warden restart"
                fi
        fi
        if [ "$RUNNING" == "false" ]
        then
                # Container was started earlier but is not running now.
                # Start the container. Change the client side settings
                # Change the server side settings
                docker start ${CID}
                echo "Please enter the local sudo password for $(whoami)"
                sudo sed -i '' '/'${hostName}'/d' /etc/hosts &>/dev/null
                sudo sh -c "echo  \"${IP}       ${hostName}  ${clusterName}\" >> /etc/hosts"
                sudo sed -i '' '/'${hostName}'/d' /opt/mapr/conf/mapr-clusters.conf &>/dev/null
        sudo /opt/mapr/server/configure.sh -c -C ${hostName}  -N ${clusterName} > /dev/null 2>&1
        # Change the external IP in the container
                echo "Please enter the root password of the container 'mapr' "
                ssh root@localhost -p 2222 " sed -i \"s/MAPR_EXTERNAL=.*/MAPR_EXTERNAL=${IP}/\" /opt/mapr/conf/env.sh "
                echo "Please enter the root password of the container 'mapr' "
        ssh root@localhost -p 2222 "service mapr-warden restart"
        fi
else
        # There is no instance of dev-sandbox-container running. Start a fresh container and configure client.
        runMaprImage

        sudo /opt/mapr/server/configure.sh -c -C ${hostName}  -N ${clusterName} > /dev/null 2>&1
        sudo sed -i '' '/'${hostName}'/d' /etc/hosts &>/dev/null
        sudo  sh -c "echo  \"${IP}      ${hostName}  ${clusterName}\" >> /etc/hosts"
        sudo sed -i '' '/'${hostName}'/d' /opt/mapr/conf/mapr-clusters.conf &>/dev/null
        
        services_up=0
        sleep_total=600
        sleep_counter=0
        if [ "$os_vers" == "Darwin" ]; then
           while [[ $sleep_counter -le $sleep_total ]]
            do
             curl -k -X GET "https://edf-installer.hpe.com:8443/rest/node/list?columns=svc" -u mapr:mapr123 &>/dev/null 
             if [ $? -ne 0 ];then
                echo "services required for Ezmeral Data fabric are  coming up"
                sleep 60;
                sleep_counter=$((sleep_counter+60))
             else
                services_up=1
                break
             fi
           done
       fi
       if [ "$os_vers" == "Linux" ]; then
           while [[ $sleep_counter -le $sleep_total ]]
            do
             curl -k -X GET https://`hostname -f`:8443/rest/node/list?columns=svc -u mapr:mapr123 &>/dev/null 
             if [ $? -ne 0 ];then
                echo "services required for Ezmeral Data fabric are  coming up"
                sleep 60;
                sleep_counter=$((sleep_counter+60))
             else
                services_up=1
                break
             fi
           done
       fi


        if [ $services_up -eq 1 ]; then
           echo
           echo "Client has been configured with the docker container."
           echo
	   if [   "${PUBLICIPV4DNS}" == "" ]; then
        	echo 
        	echo "Login to DF UI at https://"${MAPR_EXTERNAL}":8443/app/dfui using root/mapr to deploy data fabric"
        	echo "For user documentation, see https://docs.ezmeral.hpe.com/datafabric/home/installation/installation_main.html"
                echo "If the machine hosting seed node is running behind a proxy please update /etc/environment on seed node with appropriate  proxy settings accordingly"
                echo
    	   else
        	echo 
        	echo "Login to DF UI at https://"${PUBLICIPV4DNS}":8443/app/dfui using root/mapr to deploy data fabric"
        	echo "For user documentation, see https://docs.ezmeral.hpe.com/datafabric/home/installation/installation_main.html"
                echo "If the machine hosting seed node is running behind a proxy please update /etc/environment on seed node with appropriate  proxy settings accordingly"

          fi
       else
          echo 
          echo "services didnt come up in stipulated 10 mins time"
          echo "please login to the container using ssh root@localhost -p 2222 with mapr as password and check further"
          echo
          echo "once all services are up fabric UI is avilable at https://"${MAPR_EXTERNAL}":8443/app/dfui  and fabrics can be deployed using root/mapr"
          echo
          echo "If the machine hosting seed node is running behind a proxy please update /etc/environment on seed node with appropriate  proxy settings accordingly"
          echo	
       fi

    	
fi

            
   
