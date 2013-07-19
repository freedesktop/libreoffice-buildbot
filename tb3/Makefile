define runtest
./tests/$(subst SLASH,/,$(1)).py
endef

test: test-tb3SLASHrepostate test-tb3SLASHscheduler test-tb3-cli test-tb3-local-client
	@true
.PHONY: test

test-%:
	$(call runtest,$*)

.PHONY: test-%

# vim: set noet sw=4 ts=4:
