DEFAULT_GOAL := help

BUILD_SCRIPT := ./scripts/local-release.sh
REMOTE_HOST ?= macbook
REMOTE_SUBDIR ?= Desktop

.PHONY: help bundle-local-release build-local-release copy-to-macbook open-on-macbook macbook

help:
	@printf "%s\n" \
		"Targets:" \
		"  make bundle-local-release                Bundle and stage build/local-release/artifacts/Chops.app" \
		"  make copy-to-macbook REMOTE_HOST=...     Copy the staged app bundle to a remote Mac" \
		"  make open-on-macbook REMOTE_HOST=...     Open the copied app bundle on the remote Mac" \
		"  make macbook REMOTE_HOST=...             Bundle, verify, copy, and open the app on the remote Mac"

bundle-local-release:
	$(BUILD_SCRIPT) bundle

build-local-release:
	$(MAKE) bundle-local-release

copy-to-macbook:
	$(BUILD_SCRIPT) copy "$(REMOTE_HOST)" "$(REMOTE_SUBDIR)"

open-on-macbook:
	$(BUILD_SCRIPT) open "$(REMOTE_HOST)" "$(REMOTE_SUBDIR)"

macbook: bundle-local-release
	$(BUILD_SCRIPT) copy-and-open "$(REMOTE_HOST)" "$(REMOTE_SUBDIR)"
