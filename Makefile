IMAGE_REPO ?= openhorizon

SHELL := /bin/bash

EXECUTABLE := cloud-sync-service-container
TMPDIR := /tmp/

# we use a script that will give us the debian arch version since that's what the packaging system inputs
arch ?= $(shell tools/arch-tag)

# license file name
export LICENSE_FILE = LICENSE.txt

# By default we do not use cache for the anax container build, so it picks up the latest horizon deb pkgs. If you do want to use the cache: DOCKER_MAYBE_CACHE='' make anax-image
DOCKER_MAYBE_CACHE ?= --no-cache

DOCKER_REGISTRY ?= "dockerhub"
FSS_REGISTRY ?= $(DOCKER_REGISTRY)

export VERSION ?= 1.6.1
# BUILD_NUM will be added to the version if set. It can be a simple number or something like a numeric timestamp or jenkins hash.
# It can NOT contain dashes, but can contain: plus, period, and tilde.
export BUILD_NUM
# only set DISTRO if the artifact needs to be built differently for this distro. Value can be like "ubuntu" or "ubuntu.bionic". Will be appended to BUILD_NUMBER
export DISTRO

ifdef BUILD_NUM
BUILD_NUM := -$(BUILD_NUM:-%=%)
endif

# The CSS and its production container. This container is NOT used by hzn dev.
CSS_EXECUTABLE := cloud-sync-service
CSS_CONTAINER_DIR := css
CSS_IMAGE_VERSION ?= $(VERSION)$(BUILD_NUM)
CSS_IMAGE_BASE = image/cloud-sync-service
CSS_IMAGE_NAME = $(IMAGE_REPO)/$(arch)_cloud-sync-service
CSS_IMAGE = $(CSS_IMAGE_NAME):$(CSS_IMAGE_VERSION)
CSS_IMAGE_STG = $(CSS_IMAGE_NAME):testing$(BRANCH_NAME)
CSS_IMAGE_PROD = $(CSS_IMAGE_NAME):stable$(BRANCH_NAME)
# the latest tag is the same as stable
CSS_IMAGE_LATEST = $(CSS_IMAGE_NAME):latest$(BRANCH_NAME)
CSS_IMAGE_LABELS ?= --label "name=$(arch)_cloud-sync-service" --label "version=$(CSS_IMAGE_VERSION)" --label "release=0.0.1"

export TMPGOPATH ?= $(TMPDIR)$(EXECUTABLE)-gopath
export PKGPATH := $(TMPGOPATH)/src/github.com/open-horizon/$(EXECUTABLE)



# This sets the version in the go code dynamically at build time. See https://www.digitalocean.com/community/tutorials/using-ldflags-to-set-version-information-for-go-applications
GO_BUILD_LDFLAGS := -X 'github.com/open-horizon/anax/version.HORIZON_VERSION=$(VERSION)$(BUILD_NUM)'

ifdef GO_BUILD_LDFLAGS
	GO_BUILD_LDFLAGS := -ldflags="$(GO_BUILD_LDFLAGS)"
endif

ifndef verbose
.SILENT:
endif

$(CSS_EXECUTABLE): $(shell find . -name '*.go') gopathlinks
	@echo "Producing $(CSS_EXECUTABLE) given arch: $(arch) with tmpgopath $(TMPGOPATH)";
	cd $(PKGPATH) && \
	    export GOPATH=$(TMPGOPATH);
	    go get; \
	$(COMPILE_ARGS) go build $(GO_BUILD_LDFLAGS) -o $(CSS_EXECUTABLE)


css-docker-image: css-clean
	@echo "Producing CSS docker image $(CSS_IMAGE)";
	if [[ $(arch) == "amd64" ]]; then \
		docker build $(DOCKER_MAYBE_CACHE) $(CSS_IMAGE_LABELS) -t $(CSS_IMAGE) -f ./$(CSS_IMAGE_BASE)-$(arch)/Dockerfile.ubi . && \
		docker tag $(CSS_IMAGE) $(CSS_IMAGE_STG); \
	else echo "Building the CSS docker image is not supported on $(arch)"; fi



promote-css:
	@echo "Promoting $(CSS_IMAGE)"
	docker pull $(CSS_IMAGE)
	docker tag $(CSS_IMAGE) $(CSS_IMAGE_PROD)
	docker push $(CSS_IMAGE_PROD)
	docker tag $(CSS_IMAGE) $(CSS_IMAGE_LATEST)
	docker push $(CSS_IMAGE_LATEST)

css-clean:
	rm -f $(CSS_CONTAINER_DIR)/$(LICENSE_FILE)
	-docker rmi $(CSS_IMAGE) 2> /dev/null || :
	-docker rmi $(CSS_IMAGE_STG) 2> /dev/null || :

gopathlinks:
ifneq ($(GOPATH),$(TMPGOPATH))
	if [ -d "$(PKGPATH)" ] && [ "$(readlink -- "$(PKGPATH)")" != "$(CURDIR)" ]; then \
		rm $(PKGPATH); \
	fi
	if [ ! -L "$(PKGPATH)" ]; then \
		mkdir -p $(shell dirname "$(PKGPATH)"); \
		ln -s "$(CURDIR)" "$(PKGPATH)"; \
		fi
	for d in bin pkg; do \
		if [ ! -L "$(TMPGOPATH)/$$d" ]; then \
			ln -s $(GOPATH)/$$d $(TMPGOPATH)/$$d; \
		fi; \
	done
	if [ ! -L "$(TMPGOPATH)/.cache" ] && [ -d "$(GOPATH)/.cache" ]; then \
		cp -Rfpa $(GOPATH)/.cache $(TMPGOPATH)/.cache; \
	fi
endif
PKGS=$(shell cd $(PKGPATH); GOPATH=$(TMPGOPATH) go list ./... | gawk '$$1 !~ /vendor\// {print $$1}')

css-package: css-docker-image
	@echo "Packaging cloud sync service container"
	if [[ $(shell tools/image-exists $(FSS_REGISTRY) $(CSS_IMAGE_NAME) $(CSS_IMAGE_VERSION) 2> /dev/null) == 0 ]] || [ $(IMAGE_OVERRIDE) != "" ]; then \
		echo "Pushing CSS Docker image $(CSS_IMAGE)"; \
		docker push $(CSS_IMAGE); \
		docker push $(CSS_IMAGE_STG); \
	else echo "File sync service container $(CSS_IMAGE_NAME):$(CSS_IMAGE_VERSION) already present in $(FSS_REGISTRY)"; fi
