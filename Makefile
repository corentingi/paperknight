# Paperknight — single entry point. `make help` lists targets.
SHELL := /bin/bash

KOREADER_VERSION := v2026.07.1
KOREADER_TARBALL := koreader-linux-x86_64-$(KOREADER_VERSION).tar.xz
KOREADER_URL     := https://github.com/koreader/koreader/releases/download/$(KOREADER_VERSION)/$(KOREADER_TARBALL)

BUILD     := build
KOREADER  := $(BUILD)/koreader
KO_ASSETS := $(KOREADER)/lib/koreader
LUAJIT    := $(KO_ASSETS)/luajit

.PHONY: help koreader clean

help: ## List targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

koreader: $(LUAJIT) ## Download the pinned desktop KOReader into build/koreader

$(LUAJIT):
	@mkdir -p $(BUILD)/downloads $(KOREADER)
	curl -fsSL -o $(BUILD)/downloads/$(KOREADER_TARBALL) $(KOREADER_URL)
	tar -xJf $(BUILD)/downloads/$(KOREADER_TARBALL) -C $(KOREADER)
	@touch $@

clean: ## Remove build outputs (keeps downloads)
	rm -rf $(BUILD)/packs $(BUILD)/emulator-home $(BUILD)/screenshots
