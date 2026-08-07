# Crimsonland macOS port — build & run automation.
#
# `make run`      — launch the game with LÖVE (interactive play)
# `make test`     — autotest: scripted input + ASCII captures to the terminal
#                   (SCENARIO=<name> picks a src/test/scenarios/ file)
# `make extract`  — rebuild vendor/ from the original GOG rar
# `make clean`    — remove extracted vendor data (keeps the rar)

LOVE ?= $(HOME)/Applications/love.app/Contents/MacOS/love

VENDOR   := vendor
RAR      := $(VENDOR)/Crimsonland.2014.rar
SETUP    := $(VENDOR)/setup_crimsonland_2.2.0.4.exe
APP_DIR  := $(VENDOR)/extracted/app
PAKS     := $(APP_DIR)/data.pak $(APP_DIR)/data-1080p.pak \
            $(APP_DIR)/data-music-OGG_44100.pak $(APP_DIR)/data-sfx-OGG_44100.pak
STAMP    := $(VENDOR)/.extracted

.PHONY: run test extract clean check-love

run: check-love
	$(LOVE) .

SCENARIO ?= quest-smoke

test: check-love
	$(LOVE) . --autotest=$(SCENARIO)

check-love:
	@test -x "$(LOVE)" || { \
		echo "LÖVE not found at $(LOVE)"; \
		echo "Download love-11.5-macos.zip from https://github.com/love2d/love/releases"; \
		echo "and unzip to ~/Applications (NOT /Applications — Gatekeeper hangs there),"; \
		echo "or override: make run LOVE=/path/to/love"; \
		exit 1; }

extract: $(STAMP)

$(STAMP): $(PAKS)
	python3 tools/extract_pak.py $(APP_DIR)/data.pak $(VENDOR)/assets
	python3 tools/extract_pak.py $(APP_DIR)/data-1080p.pak $(VENDOR)/assets-1080p
	python3 tools/extract_pak.py $(APP_DIR)/data-music-OGG_44100.pak $(VENDOR)/assets-music
	python3 tools/extract_pak.py $(APP_DIR)/data-sfx-OGG_44100.pak $(VENDOR)/assets-sfx
	touch $@

$(PAKS): $(SETUP)
	innoextract -d $(VENDOR)/extracted $(SETUP)

$(SETUP): $(RAR)
	bsdtar -xf $(RAR) -C $(VENDOR)

clean:
	rm -rf $(VENDOR)/assets $(VENDOR)/assets-1080p $(VENDOR)/assets-music \
	       $(VENDOR)/assets-sfx $(VENDOR)/extracted $(VENDOR)/setup_crimsonland_*.exe \
	       $(STAMP)
