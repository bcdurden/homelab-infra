SHELL:=/bin/bash
REQUIRED_BINARIES := tanzu ytt kubectl kind imgpkg kapp
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell git rev-parse --show-toplevel)
BOOTSTRAP_DIR := ${ROOT_DIR}/seed
WORKLOAD_DIR := ${ROOT_DIR}/workloads
SERVICES_DIR := ${ROOT_DIR}/services
PASSWORD="overrideme"
HARBOR_VERSION="2.2.3+vmware.1-tkg.2"
HARBOR_IMAGE_URL := $(shell kubectl -n tanzu-package-repo-global get packages harbor.tanzu.vmware.com.${HARBOR_VERSION} -o jsonpath='{.spec.template.spec.fetch[0].imgpkgBundle.image}')
OPT_ARGS=""
SOPS_KEY_NAME="gitops"
GITOPS_KEY := "$(shell gpg --export-secret-keys -a gitops | base64 -w0)"


# TKG export vars
TKG_IMAGE_REPO="projects.registry.vmware.com/tkg"
TKR_VERSION="v1.21.8_vmware.1-tkg.2"
TKG_REMOTE_REPO="harbor.lab.pivotal-poc.solutions/tkg"
TKG_REMOTE_CA_FILE="/tmp/harbor.ca.crt"
TKG_TAR_FILENAME="${PWD}/airgap_images.tar"

TKG_REMOTE_CA_CERT_B64 := "$(shell cat ${TKG_REMOTE_CA_FILE} | base64 -w0)"

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. Tanzu CLI is required. See instructions at https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.5/vmware-tanzu-kubernetes-grid-15/GUID-install-cli.html")))

kind: check-tools
	@printf "\n===> Creating Kind Cluster\n";\
	kind create cluster --config $(BOOTSTRAP_DIR)/kind.yaml

deploy:
	@printf "\n===> Installing Infra Management-Cluster\n";\
	cp ${BOOTSTRAP_DIR}/overlays/docker.yaml ~/.config/tanzu/tkg/providers/ytt/09_miscellaneous/
	ytt -v vsphere_password=${PASSWORD} -f $(BOOTSTRAP_DIR)/cluster_config > /tmp/config.yaml && tanzu management-cluster create --file /tmp/config.yaml -v 6 --use-existing-bootstrap-cluster $(OPT_ARGS)

storage_class: check-tools
	@printf "\n===> Installing the default Storage Class into the Cluster\n";\
	kubectl apply -f $(BOOTSTRAP_DIR)/storageclass.yaml

metallb: check-tools
	@printf "\n===> Installing MetalLB into the Cluster\n";\
	kapp deploy -a metallb -f $(SERVICES_DIR)/metallb -y

contour: check-tools
	@printf "\n===> Installing Contour Package into the Cluster\n";\
	tanzu package install contour -p contour.tanzu.vmware.com -v 1.17.2+vmware.1-tkg.2 -f $(SERVICES_DIR)/contour/values.yaml

harbor: metallb storage_class contour
	@printf "\n===> Installing Harbor Package into the Cluster\n";\
	imgpkg pull -b ${HARBOR_IMAGE_URL} -o /tmp/harbor
	tanzu package install harbor -p harbor.tanzu.vmware.com -v 2.2.3+vmware.1-tkg.2 -f ${SERVICES_DIR}/harbor/harbor-data-values.yaml
	@printf "\n===>Placing Harbor CA Certificate at /tmp/harbor.ca.crt";
	kubectl get secret harbor-ca-key-pair -n tanzu-system-registry -o yaml | yq e '.data."ca.crt"' - | base64 -d > /tmp/harbor.ca.crt
	@printf "\n===>Injecting Harbor CA into kapp-controller as trusted";
	kc get cm kapp-controller-config -n tkg-system -o yaml | ytt -f - -f overlays/kapp_config.yaml -v harbor_ca_cert="$(kubectl get secret harbor-ca-key-pair -n tanzu-system-registry -o yaml | yq e '.data."ca.crt"' - | base64 -d)" | kubectl replace -f -

harbor_ca:
	@printf "\n===>Placing Harbor CA Certificate at /tmp/harbor.ca.crt\n";\
	kubectl get secret harbor-ca-key-pair -n tanzu-system-registry -o yaml | yq e '.data."ca.crt"' - | base64 -d > /tmp/harbor.ca.crt

sops:
	@printf "\n===>Creating SOPS master secret\n";\
	ytt -f seed/sops -v sops_key_base64=$(GITOPS_KEY) | kubectl apply -f -

install: kind deploy metallb contour harbor storage_class
	@printf "\n===> Installing Infra Management-Cluster\n";\

delete-kind: check-tools
	@printf "\n===> Removing KinD cluster\n";\
	kind delete cluster

tkg-export: check-tools
	@printf "\n===> Exporting TKG images\n";\
	pushd scripts && TKG_IMAGE_REPO=${TKG_IMAGE_REPO} TKR_VERSION=${TKR_VERSION} ./gen-airgap-images.sh > image-copy-list
	pushd scripts && ./download-images.sh image-copy-list
	pushd scripts && tar cvf airgap_images.tar *.tar && cp airgap_images.tar ../ && rm -rf *.tar && rm image-copy-list

tkg-push: check-tools 
	@printf "\n===> Pushing TKG image archive\n";\
	pushd scripts && TKG_CUSTOM_IMAGE_REPOSITORY=${TKG_REMOTE_REPO} TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE=${TKG_REMOTE_CA_CERT_B64} ./push-tar.sh ${TKG_TAR_FILENAME}