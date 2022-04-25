REQUIRED_BINARIES := tanzu ytt kubectl kind
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell git rev-parse --show-toplevel)
BOOTSTRAP_DIR := $(ROOT_DIR)/bootstrap
SERVICES_DIR := $(ROOT_DIR)/services


check-tools: ## Check to make sure you have the right tools
  $(foreach exec,$(REQUIRED_BINARIES),\
    $(if $(shell which $(exec)),,$(error "'$(exec)' not found. Tanzu CLI is required. See instructions at https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.5/vmware-tanzu-kubernetes-grid-15/GUID-install-cli.html")))

create-kind: check-tools
  @printf "\n===> Creating Kind Cluster\n";\
	kind create cluster --config $(BOOTSTRAP_DIR)/kind.yaml

deploy: create-kind
  @printf "\n===> Installing Infra Management-Cluster\n";\
	ytt -f $(BOOTSTRAP_DIR)/cluster_config | tanzu management-cluster create --file - -v 6 --use-existing-bootstrap-cluster

storage_class: check-tools
  @printf "\n===> Installing the default Storage Class into the Cluster\n";\
	kubectl apply -f $(BOOTSTRAP_DIR)/storageclass.yaml

metallb: check-tools
  @printf "\n===> Installing MetalLB into the Cluster\n";\
	kubectl apply -f $(SERVICES_DIR)/metallb

contour: check-tools
  @printf "\n===> Installing Contour Package into the Cluster\n";\
	tanzu package install contour -p contour.tanzu.vmware.com -v 1.17.2+vmware.1-tkg.2 -f $(SERVICES_DIR)/contour/values.yaml

harbor: storage_class contour
  @printf "\n===> Installing Harbor Package into the Cluster\n";\
	tanzu package install harbor -p harbor.tanzu.vmware.com -v 2.2.3+vmware.1-tkg.2 -f $(SERVICES_DIR)/harbor-data-values.yaml

install: deploy metallb harbor
  @printf "\n===> Installing Infra Management-Cluster\n";\
	ytt -f $(BOOTSTRAP_DIR)/cluster_config | tanzu management-cluster create --file - -v 6 --use-existing-bootstrap-cluster

uninstall: create-kind
  @printf "\n===> Destroying Infra Management-Cluster\n";\
	tanzu management-cluster delete --use-existing-cleanup-cluster