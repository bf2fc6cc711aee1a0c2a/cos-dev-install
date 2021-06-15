## Makefile path and dir
MKFILE_PATH := $(realpath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(realpath $(dir $(MKFILE_PATH)))

## default source directory, assuming all bf2 projects are kept in the same basedir
SOURCES_DIR := $(MKFILE_DIR)/work

## overlay directory name, empty by default to build base kustomizations
OVERLAY :=

## save or apply kustomized resources
KUBECTL_APPLY := false
OUTPUT_DIR := $(MKFILE_DIR)/out
OUTPUT_FILE := $(OVERLAY)out.yaml

## manifests
# TODO add non-existent cos-fleetshard-meta-debezium main branch
MANIFESTS_PATH := $(MKFILE_DIR)/manifests
MANIFEST_DIRS := $(wildcard $(MANIFESTS_PATH)/*)
MANIFEST_NAMES := $(MANIFEST_DIRS:$(MANIFESTS_PATH)/%=%)
MANIFEST_YMLS := $(MANIFEST_DIRS:%=%/*.yml)

## source repos and branches
REPO_BASE := git@github.com:bf2fc6cc711aee1a0c2a
REPO_BRANCH := main
GIT_PULL := false
SOURCES_DIRS := $(MANIFEST_NAMES:%=$(SOURCES_DIR)/%/)

## kustomizations
BASE_KUSTOMIZATIONS := $(MANIFEST_DIRS:%=%/kustomization.yaml)

.PHONY: all checkout_branches checkout_repo_* kustomize $(MANIFEST_NAMES) clean clean-work

## don't delete intermediate targets
#.PRECIOUS: $(SOURCES_DIR)/%

## run everything
all: | $(SOURCES_DIRS) checkout_branches kustomize

## checkout source from github if needed
$(SOURCES_DIR)/%/:
	git clone $(REPO_BASE)/$(notdir $(@D)).git -b $(REPO_BRANCH) $(@D)

## switch to required branches
checkout_branches: $(MANIFEST_NAMES:%=checkout_repo_%)

checkout_repo_%:
	git -C $(SOURCES_DIR)/$* checkout -q $(REPO_BRANCH)
ifeq ($(GIT_PULL),true)
	git -C $(SOURCES_DIR)/$* pull
endif

## run kustomize
kustomize: $(MANIFEST_NAMES) $(BASE_KUSTOMIZATIONS)

.FORCE:

$(BASE_KUSTOMIZATIONS): .FORCE | $(OUTPUT_DIR)
ifeq ($(KUBECTL_APPLY),true)
	kubectl apply --kustomize $(@D)/$(OVERLAY)
else
	kubectl kustomize $(@D)/$(OVERLAY) -o $(OUTPUT_DIR)/$(notdir $(@D))-$(OUTPUT_FILE)
endif

## make sure output dir exists
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

##########################################
## manifest targets to copy manifest files
##########################################

# Camel catalogs
CML_CATALOG_DIR := $(MANIFESTS_PATH)/cos-fleet-catalog-camel
CML_CATALOG_PREFIX := connector-catalog-camel-

cos-fleet-catalog-camel: $(MANIFESTS_PATH)/cos-fleet-catalog-camel/configs

$(CML_CATALOG_DIR)/configs: $(SOURCES_DIR)/cos-fleet-catalog-camel/cos-fleet-catalog-camel/src/generated/resources/*
	$(foreach CFG, $?, \
		cp -R $(CFG) $(CML_CATALOG_DIR)/configs/$(subst cos-fleet-catalog-camel-,$(CML_CATALOG_PREFIX),$(notdir $(CFG))) ;)
	echo $(subst cos-fleet-catalog-camel-,$(CML_CATALOG_PREFIX),$(notdir $?))
	cd $(CML_CATALOG_DIR) ; $(foreach CFG, $(subst cos-fleet-catalog-camel-,$(CML_CATALOG_PREFIX),$(notdir $?)), \
		oc create configmap $(CFG) --from-file=configs/$(CFG) -o yaml --dry-run > $(CFG).yaml &&\
		kustomize edit add resource $(CFG).yaml; )
	touch $(CML_CATALOG_DIR)/configs/*

# Debezium catalogs
DBZ_CATALOG_DIR := $(MANIFESTS_PATH)/cos-fleet-catalog-debezium
DBZ_CATALOG_PREFIX := connector-catalog-debezium-

cos-fleet-catalog-debezium: $(MANIFESTS_PATH)/cos-fleet-catalog-debezium/configs

$(DBZ_CATALOG_DIR)/configs: $(SOURCES_DIR)/cos-fleet-catalog-debezium/src/main/resources/META-INF/resources/*
	cp -R $? $(DBZ_CATALOG_DIR)/configs
	touch $(DBZ_CATALOG_DIR)/configs/*
	cd $(DBZ_CATALOG_DIR) ; $(foreach CFG, $(notdir $?), \
		oc create configmap $(DBZ_CATALOG_PREFIX)$(CFG) --from-file=configs/$(CFG) -o yaml --dry-run > $(DBZ_CATALOG_PREFIX)$(CFG).yaml &&\
		kustomize edit add resource $(DBZ_CATALOG_PREFIX)$(CFG).yaml; )

# Fleetshard operator
FLTS_MANIFEST=$(MANIFESTS_PATH)/cos-fleetshard

cos-fleetshard: $(SOURCES_DIR)/cos-fleetshard/cos-fleetshard-operator/src/main/kubernetes/*.yml
	cp -R $? $(FLTS_MANIFEST)
	cd $(FLTS_MANIFEST) ; $(foreach YML, $(notdir $?), \
		kustomize edit add resource $(notdir $(YML)); )

cos-fleetshard-meta-camel:

cos-fleetshard-meta-debezium:

cos-ui:

KAS_DIR := $(MANIFESTS_PATH)/kas-fleet-manager

kas-fleet-manager: $(KAS_DIR)/templates
	# ignore connector-catalog-configmap.yml
	cd $(MANIFESTS_PATH)/kas-fleet-manager/ && \
	rm -f templates/connector-catalog-configmap.yml && \
	kustomize edit remove resource templates/connector-catalog-configmap.yml

$(KAS_DIR)/templates: $(SOURCES_DIR)/kas-fleet-manager/templates/*.yml
	cp $? $@
	cd $(MANIFESTS_PATH)/kas-fleet-manager/ ; $(foreach YML, $(notdir $?), \
 		kustomize edit add resource templates/$(YML); )

## clean manifest files copied from sources
# TODO complete cleanup for all manifests
clean:
	rm -f $(OUTPUT_DIR)/*$(OUTPUT_FILE)
	rm -Rf $(MKFILE_DIR)/work
	cd $(MANIFESTS_PATH)/cos-fleet-catalog-camel/ && rm -Rf configs/* && rm -f $(CML_CATALOG_PREFIX)*.yaml
	cd $(MANIFESTS_PATH)/cos-fleet-catalog-debezium/ && rm -Rf configs/* && rm -f $(DBZ_CATALOG_PREFIX)*.yaml
	cd $(MANIFESTS_PATH)/cos-fleetshard/ && rm -f *.yml
#	cd $(MANIFESTS_PATH)/cos-fleetshard-meta-camel/ && rm -f *.yml
#	cd $(MANIFESTS_PATH)/cos-type-service-camel/ && rm -f *.yml
#	cd $(MANIFESTS_PATH)/cos-type-service-debezium/ && rm -f *.yml
#	cd $(MANIFESTS_PATH)/cos-ui/ && rm *.yml
	cd $(MANIFESTS_PATH)/kas-fleet-manager/ && rm -f templates/*.yml

debug:
	$(foreach var,$(.VARIABLES),$(info $(var) = $($(var))))