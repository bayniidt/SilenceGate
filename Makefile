APP  := SilenceGate.app
BIN  := .build/release/SilenceGate

.PHONY: all build app run probe selftest install clean

all: app

build:
	swift build -c release

app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp Info.plist "$(APP)/Contents/Info.plist"
	@cp "$(BIN)" "$(APP)/Contents/MacOS/SilenceGate"
	@codesign --force --sign - "$(APP)" 2>/dev/null || true
	@echo "✅ 已打包 $(APP)"

run: app
	@open "$(APP)"

probe: build
	@"./$(BIN)" --probe

selftest: build
	@"./$(BIN)" --selftest

install: app
	@rm -rf "/Applications/$(APP)"
	@cp -R "$(APP)" /Applications/
	@echo "✅ 已安装到 /Applications/$(APP)"

clean:
	@rm -rf .build "$(APP)"
	@echo "已清理"
