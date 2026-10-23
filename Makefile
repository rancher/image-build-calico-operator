SEVERITIES = HIGH,CRITICAL
.DEFAULT_GOAL := build-image

UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

REPO ?= ghcr.io/rancher
DEV_CONTAINER ?= calico-operator-dev
PATCH_FILE ?= patches/0001-calico-image-tag-overrides.patch
BUILD_META=-build$(shell date +%Y%m%d)
TAG ?= ${GITHUB_ACTION_TAG}

ifeq ($(TAG),)
TAG := $(shell cat TAG)$(BUILD_META)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

DEV_IMAGE ?= $(REPO)/hardened-calico-operator:$(TAG)-dev

.PHONY: build-dev
build-dev:
	docker buildx build \
		--target operator-dev \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--tag $(DEV_IMAGE) \
		--load \
		.

.PHONY: dev-shell
dev-shell:
	docker run --name $(DEV_CONTAINER) --interactive --tty $(DEV_IMAGE)

.PHONY: export-patch
export-patch:
	@set -eu; \
		tmp="$$(mktemp "$(PATCH_FILE).XXXXXX")"; \
		trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
		docker exec $(DEV_CONTAINER) /usr/local/bin/export-operator-patch > "$$tmp"; \
		if ! test -s "$$tmp"; then \
			echo "Patch export is empty; leaving $(PATCH_FILE) unchanged" >&2; \
			exit 1; \
		fi; \
		mv "$$tmp" "$(PATCH_FILE)"

.PHONY: build-image
build-image: IMAGE = $(REPO)/hardened-calico-operator:$(TAG)
build-image:
	docker buildx build \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--tag $(IMAGE) \
		--load \
	.

.PHONY: push-image
push-image: IMAGE = $(REPO)/hardened-calico-operator:$(TAG)
push-image:
	docker buildx build \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--tag $(IMAGE) \
		--push \
		.

.PHONY: image-scan
image-scan:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(REPO)/hardened-calico-operator:$(TAG)

.PHONY: log
log:
	@echo "TARGET_PLATFORMS=$(TARGET_PLATFORMS)"
	@echo "REPO=$(REPO)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
