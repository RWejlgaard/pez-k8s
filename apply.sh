#!/bin/sh
for file in `ls **/*.yaml | grep -vE "^virtualservice-host-mutator"`
do
    kubectl apply -f $file
done
