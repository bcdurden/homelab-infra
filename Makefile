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

harbor_ca:
	@printf "\n===>Placing Harbor CA Certificate at /tmp/harbor.ca.crt\n";\
	kubectl get secret harbor-ca-key-pair -n tanzu-system-registry -o yaml | yq e '.data."ca.crt"' - | base64 -d > /tmp/harbor.ca.crt

install: kind deploy metallb contour harbor storage_class
	@printf "\n===> Installing Infra Management-Cluster\n";\

delete-kind: check-tools
	@printf "\n===> Removing KinD cluster\n";\
	kind delete cluster