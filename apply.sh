#!/bin/sh
for file in `ls **/*.yaml | grep -vE "^(virtualservice-host-mutator|k3s)"`
do
    kubectl apply -f $file
done
