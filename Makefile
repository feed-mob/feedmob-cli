RUBY = rbenv exec ruby
GEM = rbenv exec gem
PREFIX ?= $(HOME)/.local
GEM_HOME ?= $(PREFIX)/share/feedmob-cli/gems
GEM_BIN = $(GEM_HOME)/bin
VERSION := $(shell $(RUBY) -Ilib -r feedmob/cli/version -e 'print FeedMob::CLI::VERSION')
GEM_FILE = feedmob-cli-$(VERSION).gem

.PHONY: build install-local

build:
	$(GEM) build feedmob-cli.gemspec

install-local: build
	mkdir -p "$(GEM_BIN)" "$(PREFIX)/bin"
	$(GEM) install --no-document --install-dir "$(GEM_HOME)" --bindir "$(GEM_BIN)" "$(GEM_FILE)"
	printf '%s\n' '#!/bin/sh' 'export GEM_HOME="$(GEM_HOME)"' 'export GEM_PATH="$(GEM_HOME)"' 'exec "$(GEM_BIN)/fm" "$$@"' > "$(PREFIX)/bin/fm"
	chmod +x "$(PREFIX)/bin/fm"
