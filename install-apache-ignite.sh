#!/bin/bash

echo "Args: AZURE_BLOB_URL AMBARI_ADMIN AMBARI_PWD AMBARI_HOST AMBARI_CLUSTER"

function package_exists() {
    return dpkg -l "$1" &> /dev/null
}

if ! package_exists xmlstarlet ; then
	sudo apt install xmlstarlet
fi


IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin"
export IGNITE_HOME_DIR="/hadoop/ignite"

if [ -z "$1" ]; then
  export FS_DEFAULT_DFS="default wasb://"
else 
  export FS_DEFAULT_DFS="$1"
fi
if [ -z "$2" ]; then
  export AMBARI_ADMIN="default admin username"
else 
  export AMBARI_ADMIN="$2"
fi
if [ -z "$3" ]; then
  export AMBARI_PWD="default password"
else 
  export AMBARI_PWD="$3"
fi
if [ -z "$4" ]; then
  export AMBARI_HOST="default IP address or FQDN"
else 
  export AMBARI_HOST="$4"
fi
if [ -z "$5" ]; then
  export AMBARI_CLUSTER="default Ambari Cluster Name"
else 
  export AMBARI_CLUSTER="$5"
fi

#remove before installing
if [ -d "$IGNITE_HOME_DIR/$IGNITE_BINARY" ]; then 
	echo "Removing existing Ignite binaries: $IGNITE_HOME_DIR/$IGNITE_BINARY"
	sudo rm -r $IGNITE_HOME_DIR/$IGNITE_BINARY
	sudo rm $IGNITE_HOME_DIR/$IGNITE_BINARY.zip; 
fi

#install ignite
#COMMANDS="

sudo mkdir -p /hadoop/ignite/
sudo wget -P $IGNITE_HOME_DIR https://www.apache.org/dist/ignite/1.7.0/apache-ignite-hadoop-1.7.0-bin.zip;
sudo unzip $IGNITE_HOME_DIR/$IGNITE_BINARY.zip -d $IGNITE_HOME_DIR;

echo "Creating IGNITE and HADOOP envvars"
#export important variables
export IGNITE_HOME="$IGNITE_HOME_DIR/$IGNITE_BINARY";

if [ ! -d "$IGNITE_HOME" ]; then
  echo "Ignite couldn't be extracted"
  exit -1
fi

sudo find $IGNITE_HOME -type d -exec sudo chmod 755 {} \;
sudo find $IGNITE_HOME -type f -exec sudo chmod 755 {} \;
sudo ls -al $IGNITE_HOME/*

export HADOOP_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_COMMON_HOME="/usr/hdp/current/hadoop-client";
export HADOOP_HDFS_HOME="/usr/hdp/current/hadoop-hdfs-client";
export HADOOP_MAPRED_HOME="/usr/hdp/current/hadoop-mapreduce-client";

echo "IGNITE_HOME=$IGNITE_HOME"
echo "HADOOP_HOME=$HADOOP_HOME"
echo "HADOOP_COMMON_HOME=$HADOOP_COMMON_HOME"
echo "HADOOP_HDFS_HOME=$HADOOP_HDFS_HOME"
echo "HADOOP_MAPRED_HOME=$HADOOP_MAPRED_HOME"
echo "FS_DEFAULT_FS=$FS_DEFAULT_DFS"

echo "Creating Ignite Symlinks into Hadoop Libs"
cd $HADOOP_HOME/lib;
sudo ln -sf $IGNITE_HOME/libs/ignite-core-1.7.0.jar;
sudo ln -sf $IGNITE_HOME/libs/ignite-shmem-1.0.0.jar;
sudo ln -sf $IGNITE_HOME/libs/ignite-hadoop/ignite-hadoop-1.7.0.jar;

#backup spark-env.sh
cd $SPARK_HOME/conf;
sudo cp spark-env.sh spark-env.sh.backup_$(date +%Y%m%d_%H%M%S);

sudo su spark <<'EOF'
sed -i -e '$a\' $SPARK_HOME/conf/spark-env.sh

IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin"
export IGNITE_HOME="/hadoop/ignite/$IGNITE_BINARY";
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
sudo cp core-site.xml core-site.xml.beforeignite_$(date +%Y%m%d_%H%M%S);

#sudo su hdfs <<'EOF'
#IGNITE_BINARY="apache-ignite-hadoop-1.7.0-bin"
#export IGNITE_HOME="/hadoop/ignite/$IGNITE_BINARY";
#export HADOOP_HOME="/usr/hdp/current/hadoop-client";
#export HADOOP_COMMON_HOME="/usr/hdp/current/hadoop-client";
#export HADOOP_HDFS_HOME="/usr/hdp/current/hadoop-hdfs-client";
#export HADOOP_MAPRED_HOME="/usr/hdp/current/hadoop-mapreduce-client";


#backup hadoop core-sitE.XML
#sudo cp $HADOOP_HOME/conf/core-site.xml $HADOOP_HOME/conf/core-site.xml.beforeignite_$(date +%Y%m%d_%H%M%S);

#append ignite hadoop properties
#sed '/<\/configuration>/i <property><name>fs.igfs.impl</name><value>org.apache.ignite.hadoop.fs.v1.IgniteHadoopFileSystem</value></property><property><name>fs.AbstractFileSystem.igfs.impl</name><value>org.apache.ignite.hadoop.fs.v2.IgniteHadoopFileSystem</value></property>' $HADOOP_HOME/conf/core-site.xml > ~/sedhdfs.out;
#EOF
#sudo cp /home/hdfs/sedhdfs.out $HADOOP_CONF_DIR/core-site.xml
#sudo chown hdfs:hadoop $HADOOP_CONF_DIR/core-site.xml

#update core-site.xml with Ignite info
sudo /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_ADMIN -p $AMBARI_PWD -port 8080 set $AMBARI_HOST $AMBARI_CLUSTER core-site fs.igfs.impl org.apache.ignite.hadoop.fs.v1.IgniteHadoopFileSystem;

sudo /var/lib/ambari-server/resources/scripts/configs.sh -u $AMBARI_ADMIN -p $AMBARI_PWD -port 8080 set $AMBARI_HOST $AMBARI_CLUSTER core-site fs.AbstractFileSystem.igfs.impl org.apache.ignite.hadoop.fs.v2.IgniteHadoopFileSystem;

echo "Hadoop core-site.xml is updated.."

#append and change ignite default config xml
cd $IGNITE_HOME;
sudo sed '/^\s*<!--/!b;N;/name="secondaryFileSystem"/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' config/default-config.xml > ~/ignite-default-config.xml;

echo "Uncommented Secondary File System in Ignite default-config.xml"

cd ~/;
#replace hdfs path
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -u "//x:property[@value='hdfs://your_hdfs_host:9000']/@value" -v "$FS_DEFAULT_DFS" ignite-default-config.xml > ignite-default-config-attr.xml;

#add new property element
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:bean[@class='org.apache.ignite.hadoop.fs.CachingHadoopFileSystemFactory']" -t elem -n property -v "" ignite-default-config-attr.xml > ignite-default-config-emptyprop.xml

#add configPaths attribute to the empty property element
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -a "//x:bean[@class='org.apache.ignite.hadoop.fs.CachingHadoopFileSystemFactory']/x:property[not(@value='$FS_DEFAULT_DFS')]" -t attr -n name -v "configPaths" ignite-default-config-emptyprop.xml > ignite-default-config-prop.xml;

#add list to configPaths property
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:property[@name='configPaths']" -t elem -n list -v "" ignite-default-config-prop.xml > ignite-default-config-list.xml;

#add value element to list
xmlstarlet ed -N x="http://www.springframework.org/schema/beans" -s "//x:property[@name='configPaths']/x:list" -t elem -n value -v "/usr/hdp/current/hadoop-client/conf/core-site.xml" ignite-default-config-list.xml > default-config.xml;

echo "create a symlink for HADOOP_COMMON needed by Ignite"
sudo mkdir -p $HADOOP_HOME/share/hadoop/common/;
sudo ln -sf $HADOOP_HOME/lib $HADOOP_HOME/share/hadoop/common/
echo "created symlink from $HADOOP_HOME/share/hadoop/common/lib; to $HADOOP_HOME/lib"

cd ~/;
sudo cp ~/default-config.xml $IGNITE_HOME/config/default-config.xml;
echo "Updated Ignite default-config.xml"

cd $IGNITE_HOME;
sudo chmod 777 bin/*.sh;

echo "starting Ignite in background.."

export HADOOP_HOME="/usr/hdp/current/hadoop-client"
sudo nohup bin/ignite.sh &

exit $?
