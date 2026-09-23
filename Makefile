APP := DnDCategoriser
BUNDLE := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
# Stable self-signed identity from scripts/make-cert.sh; falls back to ad-hoc ("-") if absent.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"DnDCategoriser Dev"' && echo 'DnDCategoriser Dev' || echo '-')

VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ZIP := build/$(APP).zip

.PHONY: test app run install cert dist clean

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

# Release zip for GitHub. Ad-hoc signed and not notarized: Gatekeeper blocks it once, README has the bypass.
dist:
	$(MAKE) app SIGN_IDENTITY=-
	rm -f $(ZIP)
	ditto -c -k --keepParent $(BUNDLE) $(ZIP)
	@echo "Built $(ZIP) (version $(VERSION))"

clean:
	rm -rf build .build
