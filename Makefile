.PHONY: test install package

test:
	/bin/bash tests/run.sh

package:
	./scripts/package.sh

install:
	./install.sh --from-source .
