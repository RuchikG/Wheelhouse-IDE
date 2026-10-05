.PHONY: build test install

build:
	go build -o bin/proj ./cmd/proj

test:
	go test ./...

install: build
	mkdir -p $(HOME)/.local/bin
	ln -sf $(CURDIR)/bin/proj $(HOME)/.local/bin/proj
