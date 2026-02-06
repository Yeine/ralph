PREFIX ?= /usr/local
BATS := test/test_helper/bats-core/bin/bats
SHFMT_FLAGS := -i 2 -ci -bn -s
SOURCES := bin/ralph lib/*.sh

.PHONY: help install uninstall test test-verbose lint fmt fmt-check clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## Install ralph to $(PREFIX)/bin and $(PREFIX)/lib/ralph
	install -d "$(PREFIX)/bin"
	install -d "$(PREFIX)/lib/ralph"
	install -m 755 bin/ralph "$(PREFIX)/bin/ralph"
	install -m 644 lib/*.sh "$(PREFIX)/lib/ralph/"

uninstall: ## Remove ralph from $(PREFIX)
	rm -f "$(PREFIX)/bin/ralph"
	rm -rf "$(PREFIX)/lib/ralph"

test: $(BATS) ## Run bats test suite
	$(BATS) test/

test-verbose: $(BATS) ## Run tests with verbose output
	$(BATS) --verbose-run test/

lint: ## Run shellcheck on all sources
	shellcheck $(SOURCES)

fmt: ## Format all sources with shfmt
	shfmt -w $(SHFMT_FLAGS) $(SOURCES)

fmt-check: ## Check formatting (CI-friendly, no writes)
	shfmt -d $(SHFMT_FLAGS) $(SOURCES)

clean: ## Remove test artifacts
	rm -rf "$${TMPDIR:-/tmp}"/ralph_* "$${TMPDIR:-/tmp}"/bats-*

$(BATS):
	@echo "bats-core not found. Run: git submodule update --init --recursive"
	@exit 1
