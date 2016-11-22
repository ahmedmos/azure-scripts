#!/bin/bash

function package_exists() {
    return dpkg -l "$1" &> /dev/null
}

if ! package_exists xmlstarlet ; then
	sudo apt install xmlstarlet
fi

args=( "$@" )
if [ ${#args[@]} -lt  6 ]; then
echo "Args MUST BE: AZURE_BLOB_URL AMBARI_ADMIN AMBARI_PWD AMBARI_HOST AMBARI_CLUSTER SSH_USER WORKER_NODE1 WORKER_NODE2 ..."
  exit 1
fi

export FS_DEFAULT_DFS=${args[0]}
export AMBARI_ADMIN=${args[1]}
export AMBARI_PWD=${args[2]}
export AMBARI_HOST=${args[3]}
export AMBARI_CLUSTER=${args[4]}
export SSH_USER=${args[5]}
export WORKER_NODES=("${args[@]:6}")

export HADOOP_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_COMMON_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_HDFS_HOME="/usr/hdp/current/hadoop-hdfs-client";
export HADOOP_MAPRED_HOME="/usr/hdp/current/hadoop-mapreduce-client";

echo "IGNITE_HOME=$IGNITE_HOME"
echo "HADOOP_HOME=$HADOOP_HOME"
echo "HADOOP_COMMON_HOME=$HADOOP_COMMON_HOME"
echo "HADOOP_HDFS_HOME=$HADOOP_HDFS_HOME"
echo "HADOOP_MAPRED_HOME=$HADOOP_MAPRED_HOME"

echo "FS_DEFAULT_DFS=$FS_DEFAULT_DFS"
echo "AMBARI_ADMIN=$AMBARI_ADMIN"
echo "AMBARI_PWD=$AMBARI_PWD"
echo "AMBARI_HOST=$AMBARI_HOST"
echo "AMBARI_CLUSTER=$AMBARI_CLUSTER"
echo "SSH_USER=$SSH_USER"
echo "WORKER_NODES=${WORKER_NODES[@]}"

for node in "${WORKER_NODES[@]}"
do
  echo "node = $node"
done

IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin";
export IGNITE_HOME_DIR="/hadoop/ignite";
export IGNITE_HOME="$IGNITE_HOME_DIR/$IGNITE_BINARY";

#kill ignite if running
ignitepid=`ps -ef | grep ignite | grep default-config.xml | awk '{print $2}'`
if [ ! -z "$ignitepid" ]; then
   sudo kill -9 $ignitepid
fi

#remove before installing
if [ -d "$IGNITE_HOME" ]; then 
	echo "Removing existing Ignite binaries: $IGNITE_HOME_DIR/$IGNITE_BINARY"
	sudo rm -r $IGNITE_HOME_DIR/$IGNITE_BINARY
	sudo rm $IGNITE_HOME_DIR/$IGNITE_BINARY.zip; 
fi

#install ignite
sudo mkdir -p $IGNITE_HOME_DIR
sudo wget -P $IGNITE_HOME_DIR https://www.apache.org/dist/ignite/1.7.0/$IGNITE_BINARY.zip;
sudo unzip $IGNITE_HOME_DIR/$IGNITE_BINARY.zip -d $IGNITE_HOME_DIR;

echo "Creating IGNITE and HADOOP envvars"
#export important variables

echo "remove ignite-spark 2.11 libs.."
sudo rm -R $IGNITE_HOME/libs/ignite-spark

if [ ! -d "$IGNITE_HOME" ]; then
  echo "Ignite couldn't be extracted"
  exit -1
fi

sudo find $IGNITE_HOME -type d -exec sudo chmod 755 {} \;
sudo find $IGNITE_HOME -type f -exec sudo chmod 755 {} \;
#sudo ls -al $IGNITE_HOME/*

echo "Creating Ignite Symlinks into Hadoop Libs"
cd $HADOOP_HOME/lib;
sudo ln -sf $IGNITE_HOME/libs/ignite-core-1.7.0.jar;
sudo ln -sf $IGNITE_HOME/libs/ignite-shmem-1.0.0.jar;
sudo ln -sf $IGNITE_HOME/libs/ignite-hadoop/ignite-hadoop-1.7.0.jar;

echo "Creating Hadoop Azure Symlinks into Ignite Libs"
cd $IGNITE_HOME/libs;
sudo ln -sf /usr/hdp/current/hadoop-client/hadoop-azure.jar;
sudo ln -sf /usr/hdp/current/hadoop-client/lib/azure-storage-4.2.0.jar;
sudo ln -sf /usr/hdp/current/hadoop-client/lib/azure-keyvault-core-0.8.0.jar;

#backup spark-env.sh
echo "backing up spark-env.sh to $IGNITE_HOME"
sudo cp $SPARK_HOME/conf/spark-env.sh $IGNITE_HOME/spark-env.sh.backup.beforeignite;
	
sudo su spark <<'EOF'
sed -i -e '$a\' $SPARK_HOME/conf/spark-env.sh


IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin";
export IGNITE_HOME_DIR="/hadoop/ignite";
export IGNITE_HOME="$IGNITE_HOME_DIR/$IGNITE_BINARY";
export HADOOP_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_COMMON_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_HDFS_HOME="/usr/hdp/current/hadoop-hdfs-client";
export HADOOP_MAPRED_HOME="/usr/hdp/current/hadoop-mapreduce-client";

sed -i -e '$a\' $SPARK_HOME/conf/spark-env.sh
#append ignite libs to spark-env.sh
cat <<EOT >> $SPARK_HOME/conf/spark-env.sh

IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin"
IGNITE_HOME="/hadoop/ignite/$IGNITE_BINARY"
IGNITE_LIBS="\${IGNITE_HOME}/libs/*"
for file in \${IGNITE_LIBS}
do
    if [ -d \${file} ] && [ "\${file}" != "\${IGNITE_HOME}"/libs/optional ]; then
        IGNITE_LIBS=\${IGNITE_LIBS}:\${file}/*
    fi
done
export SPARK_CLASSPATH=\$SPARK_CLASSPATH:\$IGNITE_LIBS

EOT
EOF

echo "Spark spark-env.sh is updated.."

#backup core-site.xml
cd $HADOOP_CONF_DIR;
echo "backing up hadoop core-site to $IGNITE_HOME"
sudo cp core-site.xml $IGNITE_HOME/core-site.xml.backup.beforeignite;

#update core-site.xml with Ignite info
sudo /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_ADMIN -p $AMBARI_PWD -port 8080 set $AMBARI_HOST $AMBARI_CLUSTER core-site fs.igfs.impl org.apache.ignite.hadoop.fs.v1.IgniteHadoopFileSystem;

sudo /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_ADMIN -p $AMBARI_PWD -port 8080 set $AMBARI_HOST $AMBARI_CLUSTER core-site fs.AbstractFileSystem.igfs.impl org.apache.ignite.hadoop.fs.v2.IgniteHadoopFileSystem;

echo "Hadoop core-site.xml is updated.."

#append and change ignite default config xml
cd $IGNITE_HOME;
echo "uncommenting the secondaryFileSystem lines"
sudo sed '/^\s*<!--/!b;N;/name="secondaryFileSystem"/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' config/default-config.xml > sdfs-default-config.xml;

#enable discovery services
echo "uncommenting the discoverySpi lines"
sudo sed '/^\s*<!--/!b;N;/name="discoverySpi"/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' sdfs-default-config.xml > sdfs-dspi-default-config.xml;

#replace hdfs path
echo "change default dfs to wasb"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -u "//x:property[@value='hdfs://your_hdfs_host:9000']/@value" -v "$FS_DEFAULT_DFS" sdfs-dspi-default-config.xml > ignite-default-config-wasb.xml;

#add new property element
echo "adding new empty property element"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:bean[@class='org.apache.ignite.hadoop.fs.CachingHadoopFileSystemFactory']" -t elem -n property -v "" ignite-default-config-wasb.xml > ignite-default-config-emptyprop.xml

#add configPaths attribute to the empty property element
echo "adding configPaths attribute name to the empty property element"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -a "//x:bean[@class='org.apache.ignite.hadoop.fs.CachingHadoopFileSystemFactory']/x:property[not(@value='$FS_DEFAULT_DFS')]" -t attr -n name -v "configPaths" ignite-default-config-emptyprop.xml > ignite-default-config-prop.xml;

#add list to configPaths property
echo "adding empty list element to the configPaths prop"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:property[@name='configPaths']" -t elem -n list -v "" ignite-default-config-prop.xml > ignite-default-config-list.xml;

#add value element to list
echo "add a value element inside the list"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:property[@name='configPaths']/x:list" -t elem -n value -v "/usr/hdp/current/hadoop-client/conf/core-site.xml" ignite-default-config-list.xml > default-config-sdfs.xml;

#remove default discoverySpi entry
echo "remove default discoverySpi entry"
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -d "//x:property[@name='addresses']/x:list/x:value" default-config-sdfs.xml > default-config.xml

echo "add worker nodes ip addresses to discoverySpi"
for node in "${WORKER_NODES[@]}"
do
	#add worker nodes entries
	xmlstarlet ed --inplace -N x="http://www.springframework.org/schema/beans" -s "//x:property[@name='addresses']/x:list" -t elem -n value -v "$node:47500..47509" default-config.xml
done

sudo cp default-config.xml $IGNITE_HOME/config/default-config.xml;
echo "Updated Ignite default-config.xml"

echo "create a symlink for HADOOP_COMMON needed by Ignite"
sudo mkdir -p $HADOOP_HOME/share/hadoop/common/;
sudo ln -sf $HADOOP_HOME/lib $HADOOP_HOME/share/hadoop/common/;
echo "created symlink from $HADOOP_HOME/share/hadoop/common/lib; to $HADOOP_HOME/lib"

cd $IGNITE_HOME;
sudo chmod 777 bin/*.sh;

echo "starting Ignite in background.."

export HADOOP_HOME="/usr/hdp/current/hadoop-client"
sudo mkdir -p $IGNITE_HOME/work/;
#sudo chown -R $SSH_USER. $IGNITE_HOME/work/;
sudo chmod -R 777 $IGNITE_HOME/work/
nohup bin/ignite.sh &

exit $?
