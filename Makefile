# Development tasks for wm. Run `make` to see them.

CONFIG ?= release
# Where `make install` puts the app and the `wm` link. The app has to stay in a fixed place for start_at_login.
APP_DIR ?= /Applications
BIN_DIR ?= $(HOME)/.local/bin
# The certificate that signs the app: a name or a SHA-1 hash from `make identities`. Without it, the first
# "Apple Development" certificate of the keychain. A stable signature keeps the Accessibility permission between builds.
CODESIGN_IDENTITY ?=
IDENTITY = $(or $(CODESIGN_IDENTITY),$(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $$2; exit }'))
# Tests that hang must not hold the terminal: use timeout (or gtimeout) when there is one.
TIMEOUT := $(shell command -v timeout || command -v gtimeout)

.DEFAULT_GOAL := help
.PHONY: help deps build test install identities

help:
	@echo "make deps         check the Swift toolchain; install the tools for the icon (librsvg, imagemagick) if they are missing"
	@echo "make build        compile only (CONFIG=release|debug, default release); it does not touch the app that runs"
	@echo "make test         run the unit tests"
	@echo "make install      build, sign with the certificate, copy to $(APP_DIR)/wm.app, link wm in $(BIN_DIR), start it"
	@echo "make identities   list the code-signing certificates that you can give to CODESIGN_IDENTITY"
	@echo ""
	@echo "make install CODESIGN_IDENTITY=\"My Certificate\"   APP_DIR=~/Applications   BIN_DIR=~/bin"

deps:
	@xcode-select -p >/dev/null 2>&1 || { echo "error: no Xcode or command line tools: run xcode-select --install"; exit 1; }
	@version="$$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"; \
	[ -n "$$version" ] && [ "$$(printf '6.2\n%s\n' "$$version" | sort -V | head -1)" = "6.2" ] \
		|| { echo "error: wm needs the Swift 6.2 toolchain or newer (found: $${version:-none})"; exit 1; }; \
	echo "swift $$version: ok"
	@# Only `assets/make-icns.sh` needs these. Nothing else in the project has a dependency.
	@if command -v brew >/dev/null 2>&1; then \
		for formula in librsvg imagemagick; do \
			brew list --formula "$$formula" >/dev/null 2>&1 && echo "$$formula: ok" || brew install "$$formula"; \
		done; \
	else \
		echo "warning: no Homebrew: install librsvg and imagemagick yourself to make the icon (assets/make-icns.sh)"; \
	fi

build:
	swift build -c $(CONFIG)

test:
	$(if $(TIMEOUT),$(TIMEOUT) 300 )swift test

identities:
	@security find-identity -v -p codesigning

install:
	@test -n "$(IDENTITY)" || { \
		echo "error: no code-signing certificate. wm would be signed ad hoc and macOS would ask for Accessibility after every build."; \
		echo "hint: run 'make identities', then 'make install CODESIGN_IDENTITY=\"<name or hash>\"'"; \
		exit 1; }
	@echo "Signing with $(IDENTITY)"
	NO_START=1 CODESIGN_IDENTITY="$(IDENTITY)" ./build-app.sh $(CONFIG)
	rm -rf "$(APP_DIR)/wm.app"
	ditto .build/wm.app "$(APP_DIR)/wm.app"
	codesign --verify --deep --strict "$(APP_DIR)/wm.app"
	@codesign -dr - "$(APP_DIR)/wm.app" 2>&1 | grep 'designated =>' || true
	mkdir -p "$(BIN_DIR)"
	ln -sf "$(APP_DIR)/wm.app/Contents/MacOS/wm" "$(BIN_DIR)/wm"
	"$(APP_DIR)/wm.app/Contents/MacOS/wm" daemon start
	@echo "Installed $(APP_DIR)/wm.app and $(BIN_DIR)/wm. Make sure $(BIN_DIR) is in your PATH."
