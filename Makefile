SEVERITIES = HIGH,CRITICAL

ifeq ($(ARCH),)
ARCH=$(shell go env GOARCH)
endif

ifeq ($(OS),)
OS=$(shell go env GOOS)
endif

ifeq ($(OS),windows)
DOCKERFILE=Dockerfile.windows
else
DOCKERFILE=Dockerfile
endif

BUILD_META=-build$(shell TZ=UTC date +%Y%m%d)
ORG ?= rancher
PKG ?= github.com/containerd/containerd
SRC ?= github.com/k3s-io/containerd
TAG ?= v1.6.19-k3s1$(BUILD_META)

ifneq ($(DRONE_TAG),)
TAG := $(DRONE_TAG)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG needs to end with build metadata: $(BUILD_META))
endif

.PHONY: image-build
image-build:
	docker build \
		--pull \
		--build-arg PKG=$(PKG) \
		--build-arg SRC=$(SRC) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg ARCH=$(ARCH) \
		--build-arg ORG=$(ORG) \
		--build-arg GOOS=$(OS) \
		--tag $(ORG)/hardened-containerd:$(TAG)-$(ARCH)-$(OS) \
		--file $(DOCKERFILE) \
		.

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-containerd:$(TAG)-$(ARCH)-$(OS)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create --amend \
		$(ORG)/hardened-containerd:$(TAG) \
		$(ORG)/hardened-containerd:$(TAG)-$(ARCH)-$(OS)
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push \
		$(ORG)/hardened-containerd:$(TAG)

.PHONY: image-scan
image-scan:
	trivy --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-containerd:$(TAG)-$(ARCH)-$(OS)
