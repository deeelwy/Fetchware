# Makefile for test-dist, which is a "test distribution" for testing Fetchware's
# install, upgrade, and so on functionality.

all:
	sh -c 'echo "fetchware: make ran successfully!"'

install:
	sh -c 'echo "fetchware: make install ran successfully!"'

uninstall:
	sh -c 'echo "fetchware: make uninstall ran successfully!"'

build-package:
	sh -c 'echo "Build package and creating md5sum."'

	sh -c '(cd .. && tar --create --gzip --verbose --file test-dist-1.00.fpkg  ./Fetchwarefile test-dist-1.00)'

	sh -c '(cd .. && md5sum test-dist-1.00.fpkg > test-dist-1.00.fpkg.md5)'

