.PHONY: build test dmg install icon clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

dmg:
	./scripts/build-dmg.sh

install:
	./scripts/install-local.sh

icon:
	./scripts/generate-icon.sh

clean:
	rm -rf .build dist
