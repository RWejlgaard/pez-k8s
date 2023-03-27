#!/bin/sh
CONTEXTS="pez-london pez-copenhagen"

for CONTEXT in $CONTEXTS
do
    kubectl apply -f ./argocd/pez-k8s.yaml --context $CONTEXT
done
