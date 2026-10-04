# Paperknight — single entry point. `make help` lists targets.
SHELL := /bin/bash

KOREADER_VERSION := v2026.07.1
KOREADER_TARBALL := koreader-linux-x86_64-$(KOREADER_VERSION).tar.xz
KOREADER_URL     := https://github.com/koreader/koreader/releases/download/$(KOREADER_VERSION)/$(KOREADER_TARBALL)

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
	tar -xJf $(BUILD)/downloads/$(KOREADER_TARBALL) -C $(KOREADER)
	@touch $@

clean: ## Remove build outputs (keeps downloads)
	rm -rf $(BUILD)/packs $(BUILD)/emulator-home $(BUILD)/e2e

E2E_SCENARIOS := $(wildcard tools/emulator/scenarios/*.lua)

.PHONY: e2e emulator
e2e: koreader fixture-packs ## Headless end-to-end scenarios (screenshots in build/e2e/)
	PAPERKNIGHT_PACKS_DIR=$(abspath $(FIXTURE_PACKS)) PAPERKNIGHT_STUDIES_DIR=$(abspath plugin/tests/fixtures) \
		tools/emulator/run.sh e2e $(E2E_SCENARIOS)

emulator: koreader ## Desktop KOReader window with the plugin loaded (needs a display)
	tools/emulator/run.sh window

.PHONY: test test-lua test-py check
test-lua: koreader fixture-packs ## Lua unit tests (KOReader's LuaJIT and environment)
	cd $(KO_ASSETS) && ./luajit $(abspath plugin/tests/run.lua)

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

.PHONY: study
study: venv ## Download a Lichess study: make study ID=<id or URL> (private: LICHESS_TOKEN=...)
	@test -n "$(ID)" || { echo "usage: make study ID=<study id or URL>"; exit 2; }
	$(PIPELINE) study "$(ID)"
