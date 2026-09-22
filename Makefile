APP := DnDCategoriser
BUNDLE := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents

.PHONY: test app run clean

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

clean:
	rm -rf build .build
