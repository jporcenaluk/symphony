.PHONY: help all setup deps build fmt fmt-check lint test coverage ci dialyzer e2e check-port ports server start

MIX ?= mix
PORT ?= 4000
WORKFLOW ?= ./WORKFLOW.md
SERVER_ACK_FLAG := --i-understand-that-this-will-be-running-without-the-usual-guardrails

help:
	@echo "Targets: setup, deps, fmt, fmt-check, lint, test, coverage, dialyzer, e2e, ci, ports, server, start"

setup:
	$(MIX) setup

deps:
	$(MIX) deps.get

build:
	$(MIX) build

fmt:
	$(MIX) format

fmt-check:
	$(MIX) format --check-formatted

lint:
	$(MIX) lint

coverage:
	$(MIX) test --cover

test:
	$(MIX) test

dialyzer:
	$(MIX) deps.get
	$(MIX) dialyzer --format short

e2e:
	SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs

check-port:
	@if command -v ss >/dev/null 2>&1; then \
		listeners=$$(ss -H -ltn "sport = :$(PORT)" 2>/dev/null); \
		status=$$?; \
		if [ $$status -ne 0 ]; then \
			printf '%s\n' 'Could not check port $(PORT); continuing without port preflight.' >&2; \
		elif [ -n "$$listeners" ]; then \
			printf '%s\n' 'Port $(PORT) is already in use. Retry with make server PORT=<port>.' >&2; \
			exit 1; \
		fi; \
	elif command -v lsof >/dev/null 2>&1; then \
		if lsof -nP -iTCP:$(PORT) -sTCP:LISTEN >/dev/null 2>&1; then \
			printf '%s\n' 'Port $(PORT) is already in use. Retry with make server PORT=<port>.' >&2; \
			exit 1; \
		fi; \
	else \
		printf '%s\n' 'Could not check port $(PORT); install ss or lsof to enable the server preflight.' >&2; \
	fi

ports:
	@if command -v ss >/dev/null 2>&1; then \
		ss -ltnp; \
	elif command -v lsof >/dev/null 2>&1; then \
		lsof -nP -iTCP -sTCP:LISTEN; \
	else \
		printf '%s\n' 'Install ss or lsof to list local listening ports.' >&2; \
		exit 1; \
	fi

server: check-port
	$(MAKE) build
	./bin/symphony $(SERVER_ACK_FLAG) --port $(PORT) $(WORKFLOW)

start: server

ci:
	$(MAKE) setup
	$(MAKE) build
	$(MAKE) fmt-check
	$(MAKE) lint
	$(MAKE) coverage
	$(MAKE) dialyzer

all: ci
