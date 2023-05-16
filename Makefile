bats:
	@echo "[test] Running BATS Tests"
	@make bats.docker
	@make bats.kubernetes

bats.docker:
	@echo "[test] Running BATS Tests in docker"
	@cd test/docker && ../helpers/bats/bin/bats test.bats --print-output-on-failure

bats.kubernetes:
	@echo "[test] Running BATS Tests in kubernetes"
	@cd test/kubernetes && ../helpers/bats/bin/bats test.bats --print-output-on-failure
