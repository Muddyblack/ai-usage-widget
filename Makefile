.PHONY: help view view-h install pack tag test test-py translations check-translations lint-py run-windows macos macos-test
.DEFAULT_GOAL := help

help: ## list targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z][a-zA-Z0-9_-]+:.*##/ {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

view: ## preview widget (planar)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view; \
	else \
	  ./translate/build.sh && plasmoidviewer -a package -f planar; \
	fi

view-h: ## preview widget (horizontal)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view -- horizontal; \
	else \
	  ./translate/build.sh && plasmoidviewer -a package -f horizontal; \
	fi

install: ## install test copy to local Plasma session
	@./test_install.sh

test: ## run the provider backend contract tests
	@$(MAKE) --no-print-directory test-py
	@./tests/python-interp.test.sh
	@./tests/history-io.test.sh
	@if command -v node >/dev/null 2>&1; then node --test tests/*.test.js; \
	  else echo "skipping tests/shared-code.test.js (node not found)"; fi

test-py: ## run the portable unittest suites (also what CI runs on Windows)
	@python3 -m unittest discover -s tests/python

run-windows: ## run the Windows tray app on this machine (PySide6 via 'nix develop .#windows')
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix develop .#windows --command python3 windows/app.py; \
	else \
	  python3 windows/app.py; \
	fi

macos: ## build AI Usage.app (macOS only; --arch arm64 for a fast local build)
	@macos/scripts/build-app.sh $(ARGS)

macos-test: ## run the macOS frontend's Swift suites (macOS only)
	@swift test --package-path macos

translations: ## regenerate template.pot from sources and compile the .mo catalogs
	@./translate/Messages.sh
	@./translate/build.sh

check-translations: ## fail if a locale catalog has untranslated/fuzzy entries
	@./translate/check.sh

lint-py: ## lint + format-check the Python backend, frontends and helpers (dev only, needs ruff)
	@if command -v ruff >/dev/null 2>&1; then \
	  ruff check package/contents/tools/aiusage windows macos scripts tests/python && \
	  ruff format --check package/contents/tools/aiusage windows macos scripts tests/python; \
	else \
	  echo "ruff not found — install it or run 'nix develop'"; exit 1; \
	fi

opendesktop: ## rasterize the readme SVGs to PNGs and JPGs in readme/opendesktop (needs `inkscape`)
	@readme/export_opendesktop.sh


pack: ## build .plasmoid archive
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#pack; \
	else \
	  ver=$$(grep -oE '"Version":[[:space:]]*"[^"]+"' package/metadata.json | head -1 | sed -E 's/.*"([^"]+)"$$/\1/'); \
	  name=$$(basename "$$PWD"); \
	  out="$$PWD/$$name-$$ver.plasmoid"; \
	  rm -f "$$out"; \
	  ./translate/build.sh && \
	  (cd package && zip -r "$$out" . -x '*.swp' '*~'); \
	  echo "wrote $$out"; \
	fi

tag: ## bump version, commit, tag, push
	@./tag.sh
