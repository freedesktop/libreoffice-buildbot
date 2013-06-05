define runtest
./tests/tb3/$(1).py
endef

test: test-repostate test-scheduler test-cli
	@true
.PHONY: test

test-%:
	$(call runtest,$*)

test-cli:
	./tests/tb3-cli.py

.PHONY: test-%

# vim: set noet sw=4 ts=4:
