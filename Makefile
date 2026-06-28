SRCDIR = .

OUTPUT = $(SRCDIR)/build

ZIG_SRC = $(shell find $(SRCDIR)/src -maxdepth 2 -type f -name '*.zig' -or -name '*.h')
COMPLETION_SRC = $(SRCDIR)/completions

GWIN = $(OUTPUT)/gwin

BASE_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || cat VERSION 2>/dev/null || echo "unknown")
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
ifeq ($(GIT_BRANCH),unstable)
	FINAL_VERSION = $(BASE_VERSION)-unstable
else
	FINAL_VERSION = $(BASE_VERSION)
endif

PREFIX ?= /usr
DESTDIR ?=

BINDIR = $(PREFIX)/bin
ZSHDIR = $(DATAROOTDIR)/zsh

INSTALL ?= install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644

ZIG ?= zig
ZIG_FLAGS_RELEASE = -Doptimize=ReleaseFast

all: $(GWIN)

.PHONY: clean
clean:
	rm -rf $(OUTPUT)

.PHONY: install
install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) $(GWIN) $(DESTDIR)$(BINDIR)
	$(INSTALL) -d $(DESTDIR)$(ZSHDIR)/site-functions
	$(INSTALL_DATA) $(COMPLETION_SRC)/zsh/_gwin $(DESTDIR)$(ZSHDIR)/site-functions/_gwin

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/gwin
	rm -f $(DESTDIR)$(ZSHDIR)/site-functions/_gwin

.PHONY: dist
dist:
	@echo "Packaging source for $(FINAL_VERSION)..."
	@mkdir -p gwin-$(FINAL_VERSION)
	git archive HEAD | tar -x -C gwin-$(FINAL_VERSION)
	@echo $(FINAL_VERSION) > gwin-$(FINAL_VERSION)/VERSION
	tar -czvf gwin-$(FINAL_VERSION).tar.gz gwin-$(FINAL_VERSION)
	@rm -rf gwin-$(FINAL_VERSION)

.PHONY: deb
deb: DESTDIR=./dist
deb: install
	fpm -s dir -t deb \
		-n gwin \
		-v $(FINAL_VERSION) \
		-a amd64 \
		--maintainer "Vinicius Mayrink <vncsmyrnk@gmail.com>" \
		--description "A \"Run or raise\" CLI tool for Wayland GNOME." \
		--license "GPL-3.0" \
		--url "https://github.com/vncsmyrnk/gwin" \
		-C dist .

$(GWIN): $(ZIG_SRC)
	$(ZIG) build $(ZIG_FLAGS_RELEASE)
	@mkdir -p $(OUTPUT)
	ln -sf $(shell realpath $(SRCDIR)/zig-out/bin/gwin) $@
