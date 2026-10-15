# Paperknight — single entry point. `make help` lists targets.
SHELL := /bin/bash

KOREADER_VERSION := v2026.07.1
KOREADER_TARBALL := koreader-linux-x86_64-$(KOREADER_VERSION).tar.xz
KOREADER_URL     := https://github.com/koreader/koreader/releases/download/$(KOREADER_VERSION)/$(KOREADER_TARBALL)
# the release asset's digest on GitHub (checked before extracting)
KOREADER_SHA256  := 299aadb28147a25e9432ced1214ea444a4184393b5ae97cf42402c8a61b1a1b0

BUILD     := build
KOREADER  := $(BUILD)/koreader
KO_ASSETS := $(KOREADER)/lib/koreader
LUAJIT    := $(KO_ASSETS)/luajit

VENV      := pipeline/.venv
PY        := $(VENV)/bin/python
PIPELINE  := $(PY) -m paperknight_pipeline
FIXTURE_PACKS := $(BUILD)/packs/fixture

.PHONY: help koreader clean

help: ## List targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

koreader: $(LUAJIT) ## Download the pinned desktop KOReader into build/koreader

$(LUAJIT):
	@mkdir -p $(BUILD)/downloads $(KOREADER)
	test -f $(BUILD)/downloads/$(KOREADER_TARBALL) || { curl -fsSL -o $(BUILD)/downloads/$(KOREADER_TARBALL).part $(KOREADER_URL) && mv $(BUILD)/downloads/$(KOREADER_TARBALL).part $(BUILD)/downloads/$(KOREADER_TARBALL); }
	echo "$(KOREADER_SHA256)  $(BUILD)/downloads/$(KOREADER_TARBALL)" | sha256sum -c - || { rm -f $(BUILD)/downloads/$(KOREADER_TARBALL); exit 1; }
	tar -xJf $(BUILD)/downloads/$(KOREADER_TARBALL) -C $(KOREADER)
	@touch $@

clean: ## Remove build outputs (keeps downloads)
	rm -rf $(BUILD)/packs $(BUILD)/emulator-home $(BUILD)/e2e

E2E_SCENARIOS := $(wildcard tools/emulator/scenarios/*.lua)

.PHONY: e2e emulator
e2e: koreader fixture-packs ## Headless end-to-end scenarios (screenshots in build/e2e/)
	PAPERKNIGHT_PACKS_DIR=$(abspath $(FIXTURE_PACKS)) PAPERKNIGHT_STUDIES_DIR=$(abspath plugin/tests/fixtures) PAPERKNIGHT_REPERTOIRES_DIR=$(abspath plugin/tests/fixtures/repertoires) \
		tools/emulator/run.sh e2e $(E2E_SCENARIOS)

emulator: koreader ## Desktop KOReader window with the plugin loaded (needs a display)
	tools/emulator/run.sh window

.PHONY: test test-lua test-py check
test-lua: koreader fixture-packs ## Lua unit tests (KOReader's LuaJIT and environment)
	cd $(KO_ASSETS) && timeout 600 ./luajit $(abspath plugin/tests/run.lua)

test-py: venv ## Pipeline unit tests (pytest)
	cd pipeline && .venv/bin/pytest -q

test: test-lua test-py ## All unit tests

check: test e2e ## Everything CI runs (exit command of the dev loop)

.PHONY: venv packs fixture-packs
venv: $(VENV)/.installed ## Create the pipeline virtualenv

$(VENV)/.installed: pipeline/pyproject.toml
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -e 'pipeline[dev]'
	@touch $@

packs: venv ## Build real data packs into build/packs/ (downloads ~300 MB once)
	$(PIPELINE) puzzles

fixture-packs: venv ## Small deterministic packs for e2e tests (build/packs/fixture/)
	$(PIPELINE) puzzles --input pipeline/tests/fixtures/lichess_puzzles_sample.csv \
		--output $(FIXTURE_PACKS)/puzzles.sqlite --min-popularity -100 --min-plays 0 --max-rating-dev 500

.PHONY: study pka pkc
study: venv ## Download a Lichess study: make study ID=<id or URL> (private: LICHESS_TOKEN=...)
	@test -n "$(ID)" || { echo "usage: make study ID=<study id or URL>"; exit 2; }
	$(PIPELINE) study "$(ID)"

pka: ## Device archive build/dist/pka.tar.gz + installer build/dist/pka.sh (needs staged build/dist/all)
	tools/dist/build-pka.sh

pkc: ## Code-only device archive build/dist/pkc.tar.gz + installer build/dist/pkc.sh (keeps the assets on the device)
	tools/dist/build-pka.sh --code
