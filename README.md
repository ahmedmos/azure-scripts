# azure-scripts
This repo contains Azure management scripts for certain purposes.

#install-apache-ignite.sh
This script installs Apache Ignite on HDInsight cluster regardless how many nodes it contain.
It is recommended to run this script as a ScriptAction after provisioning the cluster as it needs information about either the FQDN or IP addresses of both the name & worker nodes.
