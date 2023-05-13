bats:
	@echo "[test] Running BATS Tests"
	@cd test/docker && ../helpers/bats/bin/bats test.bats --print-output-on-failure
