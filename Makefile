APP := DnDCategoriser
BUNDLE := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
# Stable self-signed identity from scripts/make-cert.sh; falls back to ad-hoc ("-") if absent.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"DnDCategoriser Dev"' && echo 'DnDCategoriser Dev' || echo '-')

.PHONY: test app run install cert clean

cert:
	./scripts/make-cert.sh

test:
	swift test

app:
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	codesign --force --deep --sign "$(SIGN_IDENTITY)" $(BUNDLE)
	@echo "Built $(BUNDLE) signed with '$(SIGN_IDENTITY)'"

run: app
	open $(BUNDLE)

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/$(APP).app
	@echo "Installed /Applications/$(APP).app"

clean:
	rm -rf build .build
