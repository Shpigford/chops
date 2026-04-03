DEFAULT_GOAL := help

BUILD_SCRIPT := ./scripts/local-release.sh
REMOTE_HOST ?= macbook
REMOTE_SUBDIR ?= Desktop

.PHONY: help build-local-release copy-to-macbook macbook

help:
	@printf "%s\n" \
		"Targets:" \
		"  make build-local-release                 Build and stage build/local-release/artifacts/Chops.app" \
		"  make copy-to-macbook REMOTE_HOST=...     Copy the staged app bundle to a remote Mac" \
		"  make macbook REMOTE_HOST=...             Build, verify, and copy to the remote Mac on success"

build-local-release:
	$(BUILD_SCRIPT) build

copy-to-macbook:
	$(BUILD_SCRIPT) copy "$(REMOTE_HOST)" "$(REMOTE_SUBDIR)"

macbook: build-local-release
	$(BUILD_SCRIPT) copy "$(REMOTE_HOST)" "$(REMOTE_SUBDIR)"
