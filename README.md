Cos Development Install
----
[![Build All](https://github.com/bf2fc6cc711aee1a0c2a/cos-dev-install/actions/workflows/build.yaml/badge.svg)](https://github.com/bf2fc6cc711aee1a0c2a/cos-dev-install/actions/workflows/build.yaml)

Makefile and kustomizations for installing `cos-*` projects in a development environment.

## Prerequisites

- [ocm cli](https://github.com/openshift-online/ocm-cli/releases) - ocm command line tool. 
- [oc cli](https://docs.openshift.com/container-platform/4.7/cli_reference/openshift_cli/getting-started-cli.html#installing-openshift-cli) - oc command line tool. 
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) - kustomize command line tool. 
- [docker cli](https://docs.docker.com/get-docker/) - docker to create images, etc.
- [git cli](https://git-scm.com/downloads) git command line tool to clone `cos-*` project repositories. 
- [jq cli](https://stedolan.github.io/jq/download/) jq command line tool to process json. 

## Introduction

The purpose of this project is to provide a single location to gather resources from all `cos-*` projects 
and deploy them to an existing OpenShift cluster. It provides a simple yet powerful wrapper using 
[kustomizations](https://kustomize.io/) to allow working with all cos-* project configuration in a standard fashion. 
It aims to make this task trivial for the first time user with a working base kustomization, 
while being comprehesive and powerful enough for the experienced `cos-*` project developer using overlays. 

This project does not propose to move kubernetes resources from individual `cos-*` projects. 
Instead it consolidates those resources in a single place to provide a complete picture of all the resources 
for use in a development or testing environment. It also aims to make configuration and setup deterministic 
and repeatable by explicitly configuring changes through kustomizations. 

It supports running kustomizations and overlays on all `cos-*` projects and deploying the resulting resources 
to an OpenShift cluster. This project uses a simple Makefile wrapper as a universal tool for performing all the tasks 
required for deploying resources. There are also a number of different makefile targets that allow users to 
break down the entire process into stages. 

This project kustomizes resources for the following cos-* projects in the `manifests` directory:

- cos-fleet-catalog-camel
- cos-fleet-catalog-debezium
- cos-fleet-manager
- cos-fleetshard
- cos-fleetshard-meta-camel
- cos-fleetshard-meta-debezium

## Stages
The deployment process consists of the following stages and associated targets:

### Clone - `clone` and `clone/cos-*`
Clones source for all or a specific cos-* project into `$(OUTPUT_DIR)`.

### Checkout -`checkout` and `checkout/cos-*`
Checkout `$(REPO_BRANCH)` in all or a specific cos-* project.

### Update - `update` and `update/cos-*`
Updates resource and manifest files for all or specific cos-* project from cloned sources.

### Kustomize - `kustomize`
Run kustomizations on all cos-* manifests and associated resources.

### Deploy - `deploy` and `deploy/cos-*`
Deploys all or a specific cos-* project in target OpenShift cluster.
The target `deploy/cos-fleet-manager` deploys cos-fleet-manager templates. 
Use the target `deploy/fleet-manager-template` to create and install resources using those templates.

## Undeploy - `undeploy` `undeploy/cos-*`
Undeploys all or a specific cos-* project from target OpenShift cluster.
Use the target `undeploy/fleet-manager-template` to uninstall resources using cos-fleet-manager templates.
The target `undeploy/cos-fleet-manager` undeploys the resources created using templates as well as the templates.

## Configure - `configure/cos-*`
Configure secrets/configmaps, etc. for individual cos-* projects.
NOTE: WIP

## Clean - `clean`, `clean/resources`, `clean/work`, `clean/all`
Cleans $(OUTPUT_DIR), manifest resources, default sources directory `work`, and everything, respectively.

### Default target - `all`
The default target runs `clean` and `kustomize`

## Parameters

The Makefile supports following parameters

| Parameter                 | Description | Default Value |
| :---                      | :---        | :---          |
| CLUSTER_ID 	            | Cluster ID of target OpenShift cluster |  $(shell oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}') |
| CONSOLE_URL 	            | Console URL of target OpenShift cluster |  $(shell oc get console cluster -o jsonpath='{.status.consoleURL}{"\n"}') |
| CONTROL_PLANE_BASE_URL 	| Control plane base URL for cos-fleet-manager service |  $(subst console-openshift-console,cos-fleet-manager-$(NAMESPACE),$(CONSOLE_URL)) |
| ENABLE_OCM_MOCK 	        | Use mock OCM in cos-fleet-manager |  true |
| ENVIRONMENT 	            | Environment name in cos-fleet-manager |  integration |
| GIT_PULL 	                | Perform `git pull` after `git checkout` |  false |
| IMAGE_REGISTRY 	        | Image registry for cos-fleet-manager |  quay.io |
| IMAGE_REPOSITORY 	        | Image repository for cos-fleet-manager |  hchirino/testapi |
| IMAGE_TAG 	            | Image tag for cos-fleet-manager |  1625088287 |
| NAMESPACE 	            | Target namespace for deploying kustomized resources |  managed-services-$(USER) |
| OUTPUT_DIR 	            | Output directory for kustomization output yaml resources |  $(MKFILE_DIR)/out |
| OUTPUT_FILE 	            | Output file suffix |  $(OVERLAY)out.yaml |
| OVERLAY 	                | Kustomization overlay to use |  |
| REPLICAS 	                | Number of replicas for cos-fleet-manager |  1 |
| REPO_BASE 	            | Base URL for cloning cos-* projects |  git@github.com:bf2fc6cc711aee1a0c2a |
| REPO_BRANCH 	            | Branch/tag to checkout for cos-* projects |  main |
| SOURCES_DIR 	            | Work directory for cloning cos-* projects |  $(MKFILE_DIR)/work |

## Limitations
The project cos-ui is not supported at present.