# Build the release tarball that the loader self-update points at.
PKG := illogical-impulse-plugins
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)

.PHONY: dist clean check

dist:
	@rm -rf dist && mkdir -p dist
	tar --transform="s|^\.|$(PKG)|" \
	    --exclude=dist --exclude=.git --exclude=.github --exclude='*.tar.gz' \
	    -czf dist/$(PKG).tar.gz .
	@echo "built: dist/$(PKG).tar.gz ($(VERSION))"

check:
	@bash -n install.sh
	@bash -n uninstall.sh
	@bash -n payload/scripts/user_modules/patch.sh
	@bash -n payload/scripts/user_modules/fetch.sh
	@python3 -c 'import json; json.load(open("patches.json"))'
	@echo "syntax OK"

clean:
	rm -rf dist
