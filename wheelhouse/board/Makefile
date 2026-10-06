.PHONY: build test install install-skill

build:
	go build -o bin/proj ./cmd/proj

test:
	go test ./...

install: build
	mkdir -p $(HOME)/.local/bin
	ln -sf $(CURDIR)/bin/proj $(HOME)/.local/bin/proj

install-skill:
	mkdir -p $(HOME)/.claude/skills
	ln -sfn $(CURDIR)/skills/project-links $(HOME)/.claude/skills/project-links
