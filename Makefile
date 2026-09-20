# inflection.lua
#
# Everything here is optional tooling: `make test` needs nothing but a Lua
# interpreter. See tools/README.md for the targets that need Python.

LUA       ?= luajit
UPSTREAM  ?= $(error --upstream-src is required; clone jpvanhal/inflection 0.5.1 and pass UPSTREAM=/path)

.PHONY: test test-all test-busted bench lint format check regen golden cases rules unicode-data install clean help

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

test: ## Run the whole suite (zero dependencies)
	@$(LUA) spec/run.lua

test-busted: ## Run the suite under busted, if it is installed
	@if command -v busted >/dev/null 2>&1; then busted; \
	else echo "busted not installed (luarocks install busted); skipping"; fi

test-all: ## Run the suite under every available Lua interpreter
	@status=0; seen=""; ran=0; \
	for interp in luajit lua5.1 lua5.2 lua5.3 lua5.4 lua5.5 lua; do \
		command -v $$interp >/dev/null 2>&1 || continue; \
		version="$$($$interp -v 2>&1 | head -1 | cut -c1-24)"; \
		case " $$seen " in *" $$version "*) continue;; esac; seen="$$seen $$version"; ran=$$((ran+1)); \
		echo "== $$interp  $$version"; \
		if $$interp spec/run.lua > .test-all.out 2>&1; then \
			tail -1 .test-all.out | sed 's/^/   /'; \
		else \
			sed 's/^/   /' .test-all.out; status=1; \
		fi; \
	done; rm -f .test-all.out; \
	if [ $$ran -eq 0 ]; then echo "no Lua interpreter found"; exit 1; fi; \
	if [ $$status -ne 0 ]; then echo "test-all FAILED"; exit 1; fi; \
	echo "all $$ran interpreters green"

bench: ## Per-function timing over spec/data/corpus.txt
	@$(LUA) spec/bench.lua

check: test test-all test-busted lint ## Everything a contributor should run

lint: ## Run luacheck if it is installed
	@if command -v luacheck >/dev/null 2>&1; then \
		luacheck lua spec --no-color; \
	else echo "luacheck not installed (luarocks install luacheck); skipping"; fi

format: ## Format Lua sources with stylua if it is installed
	@if command -v stylua >/dev/null 2>&1; then \
		stylua lua spec; \
	else echo "stylua not installed; skipping"; fi

# --- code generation (needs Python 3 and the reference implementation) --------

rules: ## Regenerate lua/inflection/rules.lua from upstream
	@python3 tools/gen_rules.py --upstream-src $(UPSTREAM)

unicode-data: ## Regenerate lua/inflection/data.lua from Python's unicodedata
	@python3 tools/gen_unicode_data.py

cases: ## Re-record upstream's pytest suite into spec/data/upstream_cases.lua
	@python3 tools/gen_upstream_cases.py --upstream-src $(UPSTREAM)

golden: ## Regenerate spec/data/golden_corpus.tsv for the differential test
	@python3 tools/gen_corpus.py

regen: rules unicode-data cases golden ## Regenerate every generated file
	@echo "regenerated; run 'make test' to confirm the port still matches"

install: ## Install the rock with luarocks
	luarocks make inflection-1.0.0-1.rockspec

clean: ## Remove editor and generator droppings
	@find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -name '*.pyc' -delete 2>/dev/null || true
	@rm -f spec/data/*.actual .test-all.out
