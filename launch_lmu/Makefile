APP_DIR ?= $(HOME)/Apps/launch_lmu

.PHONY: install
install:
	install -d "$(APP_DIR)"
	install -m 755 launch_lmu.sh "$(APP_DIR)/launch_lmu.sh"
	install -m 644 README.md "$(APP_DIR)/README.md"
	@if [ -e "$(APP_DIR)/launch_lmu.env" ]; then \
		echo "Keeping existing $(APP_DIR)/launch_lmu.env"; \
	else \
		install -m 644 launch_lmu.env "$(APP_DIR)/launch_lmu.env"; \
	fi

.PHONY: lint fmt fmt-check check
lint:
	shellcheck launch_lmu.sh

fmt:
	shfmt -w launch_lmu.sh

fmt-check:
	shfmt -d launch_lmu.sh

# Run before committing: formatting + static analysis + syntax
check: fmt-check lint
	bash -n launch_lmu.sh
