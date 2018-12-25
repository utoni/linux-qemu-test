#! /bin/sh

GOBIN=go

if [ x"${2}" != xdeps ]; then
	#set -x
	set -e
fi

DL_TARGETS="github.com/VladimirMarkelov/clui github.com/jroimartin/gocui"
EXTRA_TARGETS="github.com/jroimartin/gocui/_examples/hello.go github.com/VladimirMarkelov/clui/demos/editfield/editfield.go"

if [ x"${2}" = xdeps ]; then
	for target in ${DL_TARGETS}; do
		echo "${GOPATH}/src/${target}"
	done

	exit 0
fi

if [ x"${2}" = xbuild -a x"${3}" != x ]; then
	echo "*** GET ${3}"
	${GOBIN} get -v -u "${3}"

	exit 0
fi

if [ x"${2}" = xextra ]; then
	for target in ${EXTRA_TARGETS}; do
		echo "*** BUILD ${GOPATH}/src/${target}"
        ${GOBIN} build -o "${GOPATH}/bin/$(basename ${target})" "${GOPATH}/src/${target}"
	done

	exit 0
fi

if [ x"${2}" = xinstall -a x"${3}" != x ]; then
	for target in ${EXTRA_TARGETS}; do
		echo "*** INSTALL ${GOPATH}/bin/$(basename ${target})"
		cp "${GOPATH}/bin/$(basename ${target})" "${3}/bin/"
	done

	exit 0
fi

exit 0
