SHELL := $(or $(shell echo $$SHELL),/bin/sh)

.PHONY: run install

install:
	chmod +x ./scripts/install.sh
	./scripts/install.sh 

run:
	chmod +x ./scripts/run.sh
	./scripts/run.sh 

