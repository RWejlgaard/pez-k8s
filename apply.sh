#!/bin/sh
for file in `ls **/*.yaml **/*.json`
do
    kubectl apply -f $file
done
