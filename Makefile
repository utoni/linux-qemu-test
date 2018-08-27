BUILDJOBS ?= 5
THIS_DIR=$(realpath .)

DL_DIR=$(THIS_DIR)/dl
BUILD_DIR=$(THIS_DIR)/build
ROOTFS_DIR=$(THIS_DIR)/rootfs
CFG_DIR=$(THIS_DIR)/config
SCRIPT_DIR=$(THIS_DIR)/scripts

LINUX_DL_PREFIX=https://cdn.kernel.org/pub/linux/kernel/v4.x
LINUX_DL_BASENAME=linux
LINUX_DL_VERSION=4.18
LINUX_DL_SUFFIX=tar.xz
LINUX_DL_URL=$(LINUX_DL_PREFIX)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_DL_FILE=$(DL_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_BUILD_DIR=$(BUILD_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION)

MUSL_DL_PREFIX=https://www.musl-libc.org/releases
MUSL_DL_BASENAME=musl
MUSL_DL_VERSION=1.1.19
MUSL_DL_SUFFIX=tar.gz
MUSL_DL_URL=$(MUSL_DL_PREFIX)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_DL_FILE=$(DL_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)
MUSL_BUILD_DIR=$(BUILD_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)

BUSYBOX_DL_PREFIX=https://busybox.net/downloads
BUSYBOX_DL_BASENAME=busybox
BUSYBOX_DL_VERSION=1.29.2
BUSYBOX_DL_SUFFIX=tar.bz2
BUSYBOX_DL_URL=$(BUSYBOX_DL_PREFIX)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_DL_FILE=$(DL_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_BUILD_DIR=$(BUILD_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION)
BUSYBOX_CFLAGS=-no-pie -I$(ROOTFS_DIR)/include -I$(ROOTFS_DIR)/usr/include -specs $(ROOTFS_DIR)/lib/musl-gcc.specs -Wno-parentheses -Wno-strict-prototypes -Wno-undef
BUSYBOX_LDFLAGS=-L$(ROOTFS_DIR)/lib -L$(ROOTFS_DIR)/usr/lib

all: pre dl extract build image

$(DL_DIR):
	mkdir -p '$@'
$(BUILD_DIR):
	mkdir -p '$@'
$(ROOTFS_DIR):
	mkdir -p '$@'
$(LINUX_BUILD_DIR):
	mkdir -p '$@'
$(MUSL_BUILD_DIR):
	mkdir -p '$@'
$(BUSYBOX_BUILD_DIR):
	mkdir -p '$@'

pre: $(DL_DIR) $(BUILD_DIR) $(ROOTFS_DIR) $(LINUX_BUILD_DIR) $(MUSL_BUILD_DIR) $(BUSYBOX_BUILD_DIR)

$(LINUX_DL_FILE):
	wget '$(LINUX_DL_URL)' -O '$@' || (rm -f '$(LINUX_DL_FILE)' && false)

$(MUSL_DL_FILE):
	wget '$(MUSL_DL_URL)' -O '$@' || (rm -f '$(MUSL_DL_FILE)' && false)

$(BUSYBOX_DL_FILE):
	wget '$(BUSYBOX_DL_URL)' -O '$@' || (rm -f '$(BUSYBOX_DL_FILE)' && false)

dl: pre $(LINUX_DL_FILE) $(MUSL_DL_FILE) $(BUSYBOX_DL_FILE)

$(LINUX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(LINUX_BUILD_DIR)' -xvf '$(LINUX_DL_FILE)' || (rm -rf '$(LINUX_BUILD_DIR)' && false)

$(MUSL_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(MUSL_BUILD_DIR)' -xvzf '$(MUSL_DL_FILE)' || (rm -rf '$(MUSL_BUILD_DIR)' && false)

$(BUSYBOX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(BUSYBOX_BUILD_DIR)' -xvjf '$(BUSYBOX_DL_FILE)' || (rm -rf '$(BUSYBOX_BUILD_DIR)' && false)

extract: dl $(LINUX_BUILD_DIR)/Makefile $(MUSL_BUILD_DIR)/Makefile $(BUSYBOX_BUILD_DIR)/Makefile

$(LINUX_BUILD_DIR)/vmlinux:
	cp -v '$(CFG_DIR)/linux.config' '$(LINUX_BUILD_DIR)/.config'
	make -C '$(LINUX_BUILD_DIR)' oldconfig
	make -C '$(LINUX_BUILD_DIR)' x86_64_defconfig
	make -C '$(LINUX_BUILD_DIR)' kvmconfig
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH=$(shell uname -m) bzImage
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(shell uname -m)' INSTALL_HDR_PATH='$(ROOTFS_DIR)/usr' headers_install

$(MUSL_BUILD_DIR)/lib/libc.so:
	cd '$(MUSL_BUILD_DIR)' && ./configure --prefix='$(ROOTFS_DIR)'
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH=$(shell uname -m) V=1 all
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH=$(shell uname -m) install

$(BUSYBOX_BUILD_DIR)/busybox:
	cp -v '$(CFG_DIR)/busybox.config' '$(BUSYBOX_BUILD_DIR)/.config'
	make -C '$(BUSYBOX_BUILD_DIR)' oldconfig
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) CONFIG_EXTRA_CFLAGS='$(BUSYBOX_CFLAGS)' CONFIG_EXTRA_LDFLAGS='$(BUSYBOX_LDFLAGS)' CONFIG_PREFIX='$(ROOTFS_DIR)' ARCH=$(shell uname -m) V=1 all
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) CONFIG_EXTRA_CFLAGS='$(BUSYBOX_CFLAGS)' CONFIG_EXTRA_LDFLAGS='$(BUSYBOX_LDFLAGS)' CONFIG_PREFIX='$(ROOTFS_DIR)' ARCH=$(shell uname -m) install

build: extract $(LINUX_BUILD_DIR)/vmlinux $(MUSL_BUILD_DIR)/lib/libc.so $(BUSYBOX_BUILD_DIR)/busybox

image: build
	cp -v '$(SCRIPT_DIR)/init.rootfs' '$(ROOTFS_DIR)/init'
	chmod 0755 '$(ROOTFS_DIR)/init'
	cd '$(ROOTFS_DIR)' && find . -print0 | cpio --null -ov --format=newc | gzip -9 > '$(THIS_DIR)/initramfs.cpio.gz'

force-rebuild:
	rm -rf '$(ROOTFS_DIR)'
	rm -f $(LINUX_BUILD_DIR)/vmlinux $(MUSL_BUILD_DIR)/lib/libc.so $(BUSYBOX_BUILD_DIR)/busybox

image-rebuild: force-rebuild build

qemu: image
	qemu-system-x86_64 -kernel '$(LINUX_BUILD_DIR)/arch/x86_64/boot/bzImage' -initrd '$(THIS_DIR)/initramfs.cpio.gz' -nographic -append "console=ttyAMA0" -enable-kvm -D ./qemu.log
