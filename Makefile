# Command Line Tools ship Swift Testing outside the default search paths; Xcode does not need these.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIBS := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_LIBS)
export TOOLCHAIN_DIR := /Library/Developer/CommandLineTools
endif

.PHONY: install
install: ## Install the lint and format tools
	brew install swiftlint swift-format

.PHONY: build
build: ## Build the library
	swift build

.PHONY: test
test: ## Run all tests
	swift test $(TEST_FLAGS) $(opts)

.PHONY: coverage
coverage: ## Verify 100% line coverage of Sources
	swift test $(TEST_FLAGS) --enable-code-coverage
	jq -e --arg sources "$(CURDIR)/Sources/" '[.data[].files[] | select(.filename | startswith($$sources))] \
		| {covered: (map(.summary.lines.covered) | add), count: (map(.summary.lines.count) | add)} \
		| (.covered * 100 / .count) as $$percent | "Line coverage: \($$percent)%" | ., ($$percent == 100)' \
		"$$(swift test $(TEST_FLAGS) --show-codecov-path)"

.PHONY: lint
lint: ## Lint and check formatting
	swiftlint --strict
	swift-format lint --strict --recursive Package.swift Sources tests

.PHONY: format
format: ## Format sources in place
	swift-format format --in-place --recursive Package.swift Sources tests

.PHONY: clean
clean: ## Remove build outputs
	swift package clean

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
