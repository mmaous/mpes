# mpes

idk, just some infra and k8s stuff. 

setting up a cluster and letting argo figure out the rest.

## what's in here

* `/infrastructure/tf/` - terraform doing terraform things (clusters, iam, etc).
* `/kubernetes/platform/` - the boring stuff (argocd, istio, observability).
* `/kubernetes/apps/` - the actual apps (eventually).

## how to use

if you really want to spin this up:

1. cd into the tf folder and `terraform apply` if you're brave.
2. point argocd at this repo.
3. go get a coffee.

pls don't break production.
