#!/bin/bash

wget http://tiny.cloudera.com/clusterdock.sh
source /dev/stdin <<< "$(curl -sL http://tiny.cloudera.com/clusterdock.sh)"

clusterdock_run ./bin/start_cluster cdh

echo "you can source the script in your SSH session and run: clusterdock_ssh node-1.cluster"
