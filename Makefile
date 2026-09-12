.PHONY: build install check package clean

build:
	./scripts/build.sh

install: build
	./scripts/install.sh

check:
	./scripts/check.sh

package: check
	./scripts/package.sh

clean:
	rm -rf build dist
