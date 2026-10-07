.PHONY: help view view-h view-hyprland hyprland install pack tag test test-py translations check-translations lint-py run-desktop run-windows macos
.DEFAULT_GOAL := help

help: ## list targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z][a-zA-Z0-9_-]+:.*##/ {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

view: ## preview widget (planar)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view; \
	else \
	  ./scripts/build-kde-package.sh && plasmoidviewer -a build/kde -f planar; \
	fi

view-h: ## preview widget (horizontal)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view -- horizontal; \
	else \
	  ./scripts/build-kde-package.sh && plasmoidviewer -a build/kde -f horizontal; \
	fi

view-hyprland: ## preview widget (Hyprland / Quickshell)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run path:.#hyprland; \
	else \
	  echo "Running the Hyprland frontend requires Nix (Quickshell runtime)." >&2; \
	  exit 1; \
	fi

hyprland: view-hyprland

install: ## install test copy to local Plasma session
	@./test_install.sh

test: ## run the provider backend contract tests
	@$(MAKE) --no-print-directory test-py
	@./tests/python-interp.test.sh
	@./tests/history-io.test.sh
	@./tests/test_install_script.sh
	@./tests/translation-provider-parity.test.sh
	@if command -v node >/dev/null 2>&1; then node --test tests/*.test.js; \
	  else echo "skipping tests/shared-code.test.js (node not found)"; fi

test-py: ## run the portable unittest suites (also what CI runs on Windows)
	@python3 -m unittest discover -s tests/python

run-desktop: ## run the desktop tray app (Windows/macOS host) on this machine (PySide6 via 'nix develop .#windows')
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix develop .#windows --command python3 hosts/desktop/app.py; \
	else \
	  python3 hosts/desktop/app.py; \
	fi

run-windows: run-desktop

macos: ## build AI Usage.app (macOS only; needs hosts/macos/build-requirements.txt)
	@hosts/macos/build-app.sh

translations: ## regenerate template.pot from sources and compile the .mo catalogs
	@./translate/Messages.sh
	@./translate/build.sh

check-translations: ## fail if a locale catalog has untranslated/fuzzy entries
	@./translate/check.sh

lint-py: ## lint + format-check the Python backend, frontends and helpers (dev only, needs ruff)
	@if command -v ruff >/dev/null 2>&1; then \
	  ruff check backend/aiusage hosts scripts tests/python && \
	  ruff format --check backend/aiusage hosts scripts tests/python; \
	else \
	  echo "ruff not found — install it or run 'nix develop'"; exit 1; \
	fi

opendesktop: ## rasterize the readme SVGs to PNGs and JPGs in docs/readme/opendesktop (needs `inkscape`)
	@docs/readme/export_opendesktop.sh


pack: ## build .plasmoid archive
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#pack; \
	else \
	  ver=$$(grep -oE '"Version":[[:space:]]*"[^"]+"' hosts/kde/metadata.json | head -1 | sed -E 's/.*"([^"]+)"$$/\1/'); \
	  name=$$(basename "$$PWD"); \
	  out="$$PWD/$$name-$$ver.plasmoid"; \
	  rm -f "$$out"; \
	  ./scripts/build-kde-package.sh && \
	  (cd build/kde && zip -r "$$out" . -x '*.swp' '*~'); \
	  echo "wrote $$out"; \
	fi

tag: ## bump version, commit, tag, push
	@./tag.sh
