SHELL := /bin/bash

.PHONY: bootstrap build test coverage export-abis demo-local demo-testnet demo-rebase demo-all verify-commits frontend-install frontend-dev frontend-build

bootstrap:
	bash scripts/bootstrap.sh

build:
	forge build

test:
	forge test

coverage:
	forge coverage --report summary

export-abis:
	bash scripts/export_abis.sh

demo-local:
	bash scripts/demo_local.sh

demo-testnet:
	bash scripts/demo_testnet.sh

demo-rebase:
	bash scripts/demo_rebase.sh

demo-all: bootstrap build test demo-local demo-rebase

verify-commits:
	bash scripts/verify_commits.sh 59

frontend-install:
	npm install --workspaces

frontend-dev:
	npm run --workspace frontend dev

frontend-build:
	npm run --workspace frontend build
