# azure-scripts
This repo contains Azure management scripts for certain purposes.

# Using install-apache-ignite.sh
This script installs [Apache Ignite](www.ignite.apache.org) on an HDInsight cluster, regardless how many your HDInsight cluster has.

The cluster is designed to run as a [ScriptAction](https://docs.microsoft.com/en-us/azure/hdinsight/hdinsight-hadoop-script-actions) **AFTER provisioning the cluster**; as it needs information about the name & worker nodes.

Running the script as a ScriptAction or manually is simple, all you need to do is submit the correct arguments separated by a space

1. The wasb storage URL of which you want Apache Ignite to interface with 
  - The URL should be as follows, you can find it in your **HDFS core-site** configuration: 
  ```
  wasb://container@account.blob.core.windows.net
  ```
2. The Ambari Admin username 
3. The Ambari Admin password
  - The Ambari Admin name & password are needed to automatically push Ignite's configuration into HDFS _core-site.xml_via Ambari's _config.sh_ command.

## Example of using the _install-apache-ignite.sh_ script
The following snippet shows how to pass the arguments for a cluster with a name: myHDICluster. The cluster consists of 2 Head nodes and 2 Worker nodes.
```bash
./install-apache-ignite.sh wasb://mycontainer@myblob.blob.core.windows.net admin AmbariPwd_01 100.8.17.254 myHDICluster adminssh 10.0.0.1 10.0.0.2 10.0.0.4 10.0.0.9
```
