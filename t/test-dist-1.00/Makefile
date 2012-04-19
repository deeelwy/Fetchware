# Makefile for test-dist, which is a "test distribution" for testing Fetchware's
# install, upgrade, and so on functionality.

all: install
	sh -c 'echo "fetchware: make ran successfully!"'

install:
	sh -c 'echo "fetchware: make install ran successfully!"'

build-package:
	tar --create --gzip --verbose --file ../test-dist-1.00.fpkg --directory .. Fetchwarefile test-dist-1.00
