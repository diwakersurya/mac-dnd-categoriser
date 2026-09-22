APP := DnDCategoriser
BUNDLE := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents

.PHONY: test app run install clean

test:
	swift test

app:
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	codesign --force --deep --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/$(APP).app
	@echo "Installed /Applications/$(APP).app"

clean:
	rm -rf build .build
