## Makefile path and dir
MKFILE_PATH := $(realpath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(realpath $(dir $(MKFILE_PATH)))

## makefile settings
.SILENT:
.DEFAULT_GOAL := all
SHELL = bash

## overlay directory name, empty by default to build base kustomizations
OVERLAY ?=

## kustomized resources output
OUTPUT_DIR ?= $(MKFILE_DIR)/out
OUTPUT_FILE ?= $(OVERLAY)out.yaml

## cluster information
NAMESPACE ?= managed-services-$(USER)
CLUSTER_ID ?= $(shell oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')
CONSOLE_URL ?= $(shell oc get console cluster -o jsonpath='{.status.consoleURL}{"\n"}')
CONTROL_PLANE_BASE_URL ?= $(subst console-openshift-console,kas-fleet-manager-$(NAMESPACE),$(CONSOLE_URL))

## cos-fleet-manager defaults
# TODO use latest for IMAGE_TAG
IMAGE_REGISTRY ?= quay.io
IMAGE_REPOSITORY ?= hchirino/testapi
IMAGE_TAG ?= 1625088287
REPLICAS ?= 1
ENVIRONMENT ?= integration
ENABLE_OCM_MOCK ?= true

## default source directory, assuming all bf2 projects are kept in the same basedir
SOURCES_DIR ?= $(MKFILE_DIR)/work

## source repos and branches
REPO_BASE ?= git@github.com:bf2fc6cc711aee1a0c2a
REPO_BRANCH ?= main
GIT_PULL ?= false

## manifests
MANIFESTS_PATH := $(MKFILE_DIR)/manifests
MANIFEST_DIRS := $(wildcard $(MANIFESTS_PATH)/*)
MANIFEST_NAMES := $(MANIFEST_DIRS:$(MANIFESTS_PATH)/%=%)
MANIFEST_YMLS := $(MANIFEST_DIRS:%=%/*.yml)

## kustomizations
KUSTOMIZATION_TARGETS := $(MANIFEST_NAMES:%=$(OUTPUT_DIR)/%-$(OUTPUT_FILE))
# helper function to generate kustomization output file name
output_filename = $(OUTPUT_DIR)/$(1)-$(OUTPUT_FILE)

## targets
CLONE_TARGETS := $(MANIFEST_NAMES:%=clone/%)
CHECKOUT_TARGETS := $(MANIFEST_NAMES:%=checkout/%)
DEPLOY_TARGETS := $(MANIFEST_NAMES:%=deploy/%)
UNDEPLOY_TARGETS := $(MANIFEST_NAMES:%=undeploy/%)
UPDATE_TARGETS := $(MANIFEST_NAMES:%=update/%)

## verify command dependencies exist
REQUIRED_BINS := ocm oc kustomize docker git jq
$(foreach bin,$(REQUIRED_BINS),\
    $(if $(shell which $(bin) 2> /dev/null),$(info Found command `$(bin)`),$(error Please install command `$(bin)`)))

## phony targets
.PHONY: all clone checkout kustomize deploy undeploy clean clean/all clean/resources clean/work
.PHONY: $(CLONE_TARGETS) $(CHECKOUT_TARGETS) $(DEPLOY_TARGETS) $(UNDEPLOY_TARGETS) $(UPDATE_TARGETS)

## forced target
.FORCE:

## run default goal to generate kustomizations
all: | kustomize

## clone repos
clone: $(SOURCES_DIR) $(CLONE_TARGETS)
	echo Cloned repos in $(SOURCES_DIR)

$(CLONE_TARGETS): PROJECT=$(notdir $@)
$(CLONE_TARGETS):
	if [[ ! -d $(SOURCES_DIR)/$(PROJECT) ]]; then git clone $(REPO_BASE)/$(PROJECT).git -b $(REPO_BRANCH) $(SOURCES_DIR)/$(PROJECT) ; fi

## make sure source dir exists
$(SOURCES_DIR):
	mkdir -p $(SOURCES_DIR)

## switch to required branches
checkout: $(CHECKOUT_TARGETS)
	echo Using git branch $(REPO_BRANCH)

$(CHECKOUT_TARGETS): PROJECT=$(notdir $@)
$(CHECKOUT_TARGETS):
	git -C $(SOURCES_DIR)/$(PROJECT) checkout -q $(REPO_BRANCH)
ifeq ($(GIT_PULL),true)
	git -C $(SOURCES_DIR)/$(PROJECT) pull
endif

## update all manifests
update: | clean/all clone checkout $(UPDATE_TARGETS)

## run kustomize
kustomize: $(KUSTOMIZATION_TARGETS)
	echo Kustomized output in $(OUTPUT_DIR)

$(KUSTOMIZATION_TARGETS): KUSTOMIZATION_DIR=$(MANIFESTS_PATH)/$(patsubst $(OUTPUT_DIR)/%-$(OUTPUT_FILE),%,$@)
$(KUSTOMIZATION_TARGETS): $(OUTPUT_DIR)
	echo Kustomizing $(KUSTOMIZATION_DIR)/$(OVERLAY)
	kustomize build $(KUSTOMIZATION_DIR)/$(OVERLAY) -o $@

## make sure output dir exists
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

## deploy everything
deploy: $(DEPLOY_TARGETS) deploy/fleet-manager-template

## deploy kustomized manifests
$(DEPLOY_TARGETS): RESOURCES_FILE=$(OUTPUT_DIR)/$(notdir $@)-$(OUTPUT_FILE)
$(DEPLOY_TARGETS): deploy/%: $(OUTPUT_DIR)/%-$(OUTPUT_FILE)
	echo Applying manifest $(RESOURCES_FILE)
	oc apply -n $(NAMESPACE) -f $(RESOURCES_FILE)

## undeploy everything
undeploy: undeploy/fleet-manager-template $(UNDEPLOY_TARGETS)

## undeploy kustomized manifests
$(UNDEPLOY_TARGETS): RESOURCES_FILE=$(OUTPUT_DIR)/$(notdir $@)-$(OUTPUT_FILE)
$(UNDEPLOY_TARGETS): undeploy/%: $(OUTPUT_DIR)/%-$(OUTPUT_FILE)
	echo Undeploying manifest $(RESOURCES_FILE)
	oc delete -n $(NAMESPACE) -f $(RESOURCES_FILE) --ignore-not-found=true

## setup additional undeploy prerequisite for cos-fleet-manager templates
undeploy/cos-fleet-manager: undeploy/fleet-manager-template

#########################
## post kustomize targets
#########################
# create secret required to run cos-fleetshard after fleet-manager has been started
FLTS_UTILS := $(SOURCES_DIR)/cos-fleetshard/etc/utils
BASE_PATH := ${CONTROL_PLANE_BASE_URL}
configure/cos-fleetshard:
	CONNECTOR_CLUSTER_ID := $(shell $(FLTS_UTILS)/create-cluster.sh)
	$(FLTS_UTILS)/create-pull-secret.sh $(CONNECTOR_CLUSTER_ID)

# helper function to check parameter
optional_param = $(if $(2), -p $(1)=$(2))

# deploy fleet manager using kustomized templates
# TODO change route template name from route in route-template.yml
deploy/fleet-manager-template: RESOURCES_FILE=$(call output_filename,cos-fleet-manager)
deploy/fleet-manager-template: deploy/cos-fleet-manager $(OUTPUT_DIR)/cos-fleet-manager-$(OUTPUT_FILE)
	echo Applying templates from $(RESOURCES_FILE)
	oc process -n $(NAMESPACE) cos-fleet-manager-db | oc apply -f - -n $(NAMESPACE)
	oc process -n $(NAMESPACE) cos-fleet-manager-secrets \
		$(call optional_param, OCM_SERVICE_CLIENT_ID,$(OCM_SERVICE_CLIENT_ID)) \
		$(call optional_param, OCM_SERVICE_CLIENT_SECRET,$(OCM_SERVICE_CLIENT_SECRET)) \
		$(call optional_param, OCM_SERVICE_TOKEN,$(OCM_SERVICE_TOKEN)) \
		$(call optional_param, OBSERVATORIUM_SERVICE_TOKEN,$(OBSERVATORIUM_SERVICE_TOKEN)) \
		$(call optional_param, AWS_ACCESS_KEY,$(AWS_ACCESS_KEY)) \
		$(call optional_param, AWS_ACCOUNT_ID,$(AWS_ACCOUNT_ID)) \
		$(call optional_param, AWS_SECRET_ACCESS_KEY,$(AWS_SECRET_ACCESS_KEY)) \
		$(call optional_param, MAS_SSO_CLIENT_ID,$(MAS_SSO_CLIENT_ID)) \
		$(call optional_param, MAS_SSO_CLIENT_SECRET,$(MAS_SSO_CLIENT_SECRET)) \
		$(call optional_param, MAS_SSO_CRT,$(MAS_SSO_CRT)) \
		$(call optional_param, ROUTE53_ACCESS_KEY,$(ROUTE53_ACCESS_KEY)) \
		$(call optional_param, ROUTE53_SECRET_ACCESS_KEY,$(ROUTE53_SECRET_ACCESS_KEY)) \
		$(call optional_param, VAULT_ACCESS_KEY,$(VAULT_ACCESS_KEY)) \
		$(call optional_param, VAULT_SECRET_ACCESS_KEY,$(VAULT_SECRET_ACCESS_KEY)) \
		| oc apply -f - -n $(NAMESPACE)
	oc process -n $(NAMESPACE) cos-fleet-manager-service \
		$(call optional_param, ENVIRONMENT,$(ENVIRONMENT)) \
		$(call optional_param, IMAGE_REGISTRY,$(IMAGE_REGISTRY)) \
		$(call optional_param, IMAGE_REPOSITORY,$(IMAGE_REPOSITORY)) \
		$(call optional_param, IMAGE_TAG,$(IMAGE_TAG)) \
		$(call optional_param, ENABLE_OCM_MOCK,$(ENABLE_OCM_MOCK)) \
		$(call optional_param, OCM_MOCK_MODE,$(OCM_MOCK_MODE)) \
		$(call optional_param, OCM_URL,$(OCM_URL)) \
		$(call optional_param, JWKS_URL,$(JWKS_URL)) \
		$(call optional_param, MAS_SSO_BASE_URL,$(MAS_SSO_BASE_URL)) \
		$(call optional_param, MAS_SSO_REALM,$(MAS_SSO_REALM)) \
		$(call optional_param, OSD_IDP_MAS_SSO_REALM,$(OSD_IDP_MAS_SSO_REALM)) \
		$(call optional_param, ALLOW_ANY_REGISTERED_USERS,$(ALLOW_ANY_REGISTERED_USERS)) \
		$(call optional_param, VAULT_KIND,$(VAULT_KIND)) \
		$(call optional_param, SERVICE_PUBLIC_HOST_URL,$(SERVICE_PUBLIC_HOST_URL)) \
		$(call optional_param, REPLICAS,$(REPLICAS)) \
		| oc apply -f - -n $(NAMESPACE)
	oc process -n $(NAMESPACE) route | oc apply -f - -n $(NAMESPACE)
	echo IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_REPOSITORY=$(IMAGE_REPOSITORY) IMAGE_TAG=$(IMAGE_TAG)

undeploy/fleet-manager-template: RESOURCES_FILE=$(call output_filename,cos-fleet-manager)
undeploy/fleet-manager-template: $(OUTPUT_DIR)/cos-fleet-manager-$(OUTPUT_FILE)
	echo Undeploying template generated resources from $(RESOURCES_FILE)
	oc process -n $(NAMESPACE) cos-fleet-manager-db | oc delete -f - -n $(NAMESPACE) --ignore-not-found=true
	oc process -n $(NAMESPACE) cos-fleet-manager-secrets | oc delete -f - -n $(NAMESPACE) --ignore-not-found=true
	oc process -n $(NAMESPACE) cos-fleet-manager-service \
		$(call optional_param, IMAGE_REGISTRY,$(IMAGE_REGISTRY)) \
		$(call optional_param, IMAGE_REPOSITORY,$(IMAGE_REPOSITORY)) \
		| oc delete -f - -n $(NAMESPACE) --ignore-not-found=true
	oc process -n $(NAMESPACE) route | oc delete -f - -n $(NAMESPACE) --ignore-not-found=true

##########################################
## manifest targets to copy manifest files
##########################################

# Camel catalogs
CML_CATALOG_DIR := $(MANIFESTS_PATH)/cos-fleet-catalog-camel
CML_CATALOG_PREFIX := connector-catalog-camel-

update/cos-fleet-catalog-camel: $(MANIFESTS_PATH)/cos-fleet-catalog-camel/configs

$(CML_CATALOG_DIR)/configs: $(SOURCES_DIR)/cos-fleet-catalog-camel/etc/connectors/
	cp -R $(wildcard $?/*) $(CML_CATALOG_DIR)/configs/
	touch $(CML_CATALOG_DIR)/configs
	cd $(CML_CATALOG_DIR) ; $(foreach CFG, $(notdir $(wildcard $?/*)), \
		oc create configmap $(CFG) --from-file=configs/$(CFG) -o yaml --dry-run > $(CFG).yaml &&\
		kustomize edit add resource $(CFG).yaml; )

# Debezium catalogs
DBZ_CATALOG_DIR := $(MANIFESTS_PATH)/cos-fleet-catalog-debezium
DBZ_CATALOG_PREFIX := connector-catalog-debezium-

update/cos-fleet-catalog-debezium: $(MANIFESTS_PATH)/cos-fleet-catalog-debezium/configs

$(DBZ_CATALOG_DIR)/configs: $(SOURCES_DIR)/cos-fleet-catalog-debezium/src/main/resources/META-INF/resources/
	cp -R $(wildcard $?/*) $(DBZ_CATALOG_DIR)/configs/
	touch $(DBZ_CATALOG_DIR)/configs
	cd $(DBZ_CATALOG_DIR) ; $(foreach CFG, $(notdir $(wildcard $?/*)), \
		oc create configmap $(DBZ_CATALOG_PREFIX)$(CFG) --from-file=configs/$(CFG) -o yaml --dry-run > $(DBZ_CATALOG_PREFIX)$(CFG).yaml &&\
		kustomize edit add resource $(DBZ_CATALOG_PREFIX)$(CFG).yaml; )

# Fleetshard operator
FLTS_MANIFEST=$(MANIFESTS_PATH)/cos-fleetshard

# TODO add missing client-id and client-secret
update/cos-fleetshard: $(FLTS_MANIFEST)
	sed -i 's/cluster-id=.*/cluster-id=$(CLUSTER_ID)/' $(FLTS_MANIFEST)/application.properties
	sed -i 's#control-plane-base-url=.*#control-plane-base-url=$(CONTROL_PLANE_BASE_URL)#' $(FLTS_MANIFEST)/application.properties

$(FLTS_MANIFEST): $(SOURCES_DIR)/cos-fleetshard/etc/kubernetes/
	cp -R $(wildcard $?/*.yml) $(FLTS_MANIFEST)
	touch $(FLTS_MANIFEST)
	cd $(FLTS_MANIFEST) ; $(foreach YML, $(notdir $(wildcard $?/*.yml)), \
		kustomize edit add resource $(notdir $(YML)); )

# Camel meta service
META_CML_MANIFEST=$(MANIFESTS_PATH)/cos-fleetshard-meta-camel

update/cos-fleetshard-meta-camel: $(META_CML_MANIFEST)

$(META_CML_MANIFEST): $(SOURCES_DIR)/cos-fleetshard-meta-camel/etc/kubernetes/
	cp -R $(wildcard $?/*.yml) $(META_CML_MANIFEST)
	touch $(META_CML_MANIFEST)
	cd $(META_CML_MANIFEST) ; $(foreach YML, $(notdir $(wildcard $?/*.yml)), \
		kustomize edit add resource $(notdir $(YML)); )

# Debezium meta service
META_DBZ_MANIFEST=$(MANIFESTS_PATH)/cos-fleetshard-meta-debezium

update/cos-fleetshard-meta-debezium: $(META_DBZ_MANIFEST)

$(META_DBZ_MANIFEST): $(SOURCES_DIR)/cos-fleetshard-meta-debezium/etc/kubernetes/
	cp -R $(wildcard $?/*.yml) $(META_DBZ_MANIFEST)
	touch $(META_DBZ_MANIFEST)
	cd $(META_DBZ_MANIFEST) ; $(foreach YML, $(notdir $(wildcard $?/*.yml)), \
		kustomize edit add resource $(notdir $(YML)); )

# TODO
update/cos-ui:

COS_MGR_DIR := $(MANIFESTS_PATH)/cos-fleet-manager

update/cos-fleet-manager: $(COS_MGR_DIR)/templates
	# ignore connector-catalog-configmap.yml
	cd $(MANIFESTS_PATH)/cos-fleet-manager/ && \
	rm -f templates/connector-catalog-configmap.yml && \
	kustomize edit remove resource templates/connector-catalog-configmap.yml

$(COS_MGR_DIR)/templates: $(SOURCES_DIR)/cos-fleet-manager/templates/
	cp $(wildcard $?/*.yml) $@
	cd $(MANIFESTS_PATH)/cos-fleet-manager/ ; $(foreach YML, $(notdir $(wildcard $?/*.yml)), \
 		kustomize edit add resource templates/$(YML); )

## clean output directory
clean:
	echo Cleaning $(OUTPUT_DIR)
	rm -f $(OUTPUT_DIR)/*$(OUTPUT_FILE)

## clean work directory
clean/work:
	echo Cleaning $(MKFILE_DIR)/work
	rm -Rf $(MKFILE_DIR)/work

## clean manifest files copied from sources
# TODO complete cleanup for all manifests
clean/resources:
	echo Cleaning resource files
	cd $(MANIFESTS_PATH)/cos-fleet-catalog-camel/ && rm -Rf configs/* && rm -f $(CML_CATALOG_PREFIX)*.yaml
	cd $(MANIFESTS_PATH)/cos-fleet-catalog-debezium/ && rm -Rf configs/* && rm -f $(DBZ_CATALOG_PREFIX)*.yaml
	cd $(MANIFESTS_PATH)/cos-fleetshard/ && rm -f *.yml
	cd $(MANIFESTS_PATH)/cos-fleetshard-meta-camel/ && rm -f *.yml
	cd $(MANIFESTS_PATH)/cos-fleetshard-meta-debezium/ && rm -f *.yml
#	cd $(MANIFESTS_PATH)/cos-ui/ && rm *.yml
	cd $(MANIFESTS_PATH)/cos-fleet-manager/ && rm -f templates/*.yml
	echo **NOTE** Use target \'update\' to update resources

## clean everything!!!
clean/all: clean clean/resources clean/work
	echo All clean!!!

debug:
	$(foreach var,$(.VARIABLES),$(info $(var) = $($(var))))
