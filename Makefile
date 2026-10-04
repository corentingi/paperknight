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
	test -f $(BUILD)/downloads/$(KOREADER_TARBALL) || { curl -fsSL -o $(BUILD)/downloads/$(KOREADER_TARBALL).part $(KOREADER_URL) && mv $(BUILD)/downloads/$(KOREADER_TARBALL).part $(BUILD)/downloads/$(KOREADER_TARBALL); }
	tar -xJf $(BUILD)/downloads/$(KOREADER_TARBALL) -C $(KOREADER)
	@touch $@

clean: ## Remove build outputs (keeps downloads)
	rm -rf $(BUILD)/packs $(BUILD)/emulator-home $(BUILD)/e2e

E2E_SCENARIOS := $(wildcard tools/emulator/scenarios/*.lua)

.PHONY: e2e emulator
e2e: koreader ## Headless end-to-end scenarios (screenshots in build/e2e/)
	tools/emulator/run.sh e2e $(E2E_SCENARIOS)

emulator: koreader ## Desktop KOReader window with the plugin loaded (needs a display)
	tools/emulator/run.sh window

.PHONY: test test-lua check
test-lua: koreader ## Lua unit tests (KOReader's LuaJIT)
	$(LUAJIT) plugin/tests/run.lua

test: test-lua ## All unit tests

check: test e2e ## Everything CI runs (exit command of the dev loop)
