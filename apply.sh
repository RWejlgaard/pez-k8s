#!/bin/sh
for file in `ls **/*.yaml`
do
    kubectl apply -f $file
done
