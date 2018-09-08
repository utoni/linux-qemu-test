ARCH=$(shell uname -m)
MEMORY ?= 64
NET_BRIDGE ?= br0
NET_HWADDR ?= 66:66:66:66:66:66
KEYMAP ?= i386/qwertz/de-latin1
LINUX_LOCAL ?=
DEFCONFIG ?=
NO_MODULES ?=

BUILDJOBS ?= $(shell cat /proc/cpuinfo | grep -o '^processor' | wc -l)
THIS_DIR=$(realpath .)

DL_DIR=$(THIS_DIR)/dl
BUILD_DIR=$(THIS_DIR)/build
ROOTFS_DIR=$(THIS_DIR)/rootfs
CFG_DIR=$(THIS_DIR)/config
SCRIPT_DIR=$(THIS_DIR)/scripts
SKEL_DIR=$(THIS_DIR)/skeleton

INITRD_TARGET=$(THIS_DIR)/initramfs.cpio.gz

LINUX_DL_PREFIX=https://cdn.kernel.org/pub/linux/kernel/v4.x
LINUX_DL_BASENAME=linux
LINUX_DL_VERSION=4.18
LINUX_DL_SUFFIX=tar.xz
LINUX_DL_URL=$(LINUX_DL_PREFIX)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_DL_FILE=$(DL_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_BUILD_DIR=$(BUILD_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION)
LINUX_TARGET=$(LINUX_BUILD_DIR)/vmlinux

MUSL_DL_PREFIX=https://www.musl-libc.org/releases
MUSL_DL_BASENAME=musl
MUSL_DL_VERSION=1.1.19
MUSL_DL_SUFFIX=tar.gz
MUSL_DL_URL=$(MUSL_DL_PREFIX)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_DL_FILE=$(DL_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_BUILD_DIR=$(BUILD_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)
MUSL_TARGET=$(MUSL_BUILD_DIR)/lib/libc.so

BUSYBOX_DL_PREFIX=https://busybox.net/downloads
BUSYBOX_DL_BASENAME=busybox
BUSYBOX_DL_VERSION=1.29.2
BUSYBOX_DL_SUFFIX=tar.bz2
BUSYBOX_DL_URL=$(BUSYBOX_DL_PREFIX)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_DL_FILE=$(DL_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_BUILD_DIR=$(BUILD_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION)
BUSYBOX_CFLAGS=-no-pie -I$(ROOTFS_DIR)/usr/include -specs $(ROOTFS_DIR)/lib/musl-gcc.specs -Wno-parentheses -Wno-strict-prototypes -Wno-undef
BUSYBOX_LDFLAGS=-L$(ROOTFS_DIR)/lib
BUSYBOX_TARGET=$(BUSYBOX_BUILD_DIR)/busybox

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
ifeq (x$(LINUX_LOCAL),x)
	wget '$(LINUX_DL_URL)' -O '$@' || (rm -f '$(LINUX_DL_FILE)' && false)
endif

$(MUSL_DL_FILE):
	wget '$(MUSL_DL_URL)' -O '$@' || (rm -f '$(MUSL_DL_FILE)' && false)

$(BUSYBOX_DL_FILE):
	wget '$(BUSYBOX_DL_URL)' -O '$@' || (rm -f '$(BUSYBOX_DL_FILE)' && false)

dl: pre $(LINUX_DL_FILE) $(MUSL_DL_FILE) $(BUSYBOX_DL_FILE)

$(LINUX_BUILD_DIR)/Makefile:
ifeq (x$(LINUX_LOCAL),x)
	tar --strip-components=1 -C '$(LINUX_BUILD_DIR)' -xvf '$(LINUX_DL_FILE)' || (rm -rf '$(LINUX_BUILD_DIR)' && false)
else
	rmdir '$(LINUX_BUILD_DIR)'
	ln -s '$(LINUX_LOCAL)' '$(LINUX_BUILD_DIR)'
endif

$(MUSL_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(MUSL_BUILD_DIR)' -xvzf '$(MUSL_DL_FILE)' || (rm -rf '$(MUSL_BUILD_DIR)' && false)

$(BUSYBOX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(BUSYBOX_BUILD_DIR)' -xvjf '$(BUSYBOX_DL_FILE)' || (rm -rf '$(BUSYBOX_BUILD_DIR)' && false)

extract: dl $(LINUX_BUILD_DIR)/Makefile $(MUSL_BUILD_DIR)/Makefile $(BUSYBOX_BUILD_DIR)/Makefile

$(LINUX_TARGET):
	cp -v '$(CFG_DIR)/linux.config' '$(LINUX_BUILD_DIR)/.config'
ifeq (x$(DEFCONFIG),x)
	make -C '$(LINUX_BUILD_DIR)' oldconfig
else
	make -C '$(LINUX_BUILD_DIR)' x86_64_defconfig
endif
	make -C '$(LINUX_BUILD_DIR)' kvmconfig
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' bzImage
ifeq (x$(NO_MODULES),x)
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules_install
endif
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_HDR_PATH='$(ROOTFS_DIR)/usr' headers_install

$(MUSL_TARGET):
	cd '$(MUSL_BUILD_DIR)' && (test -r ./config.mak || ./configure --prefix='$(ROOTFS_DIR)/usr')
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install
	test -e '$(ROOTFS_DIR)/lib' || ln -sr '$(ROOTFS_DIR)/usr/lib' '$(ROOTFS_DIR)/lib'
	test -e '$(ROOTFS_DIR)/lib/ld-musl-$(ARCH).so.1' || ln -sr '$(ROOTFS_DIR)/lib/libc.so' '$(ROOTFS_DIR)/lib/ld-musl-$(ARCH).so.1'

$(BUSYBOX_TARGET):
	cp -v '$(CFG_DIR)/busybox.config' '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_CFLAGS[ ]*=\).*,\1"$(BUSYBOX_CFLAGS)",g'   '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_LDFLAGS[ ]*=\).*,\1"$(BUSYBOX_LDFLAGS)",g' '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_PREFIX[ ]*=\).*,\1"$(ROOTFS_DIR)",g'             '$(BUSYBOX_BUILD_DIR)/.config'
	make -C '$(BUSYBOX_BUILD_DIR)' oldconfig
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install
	sed -i 's,^\(CONFIG_EXTRA_CFLAGS[ ]*=\).*,\1"",g'     '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_LDFLAGS[ ]*=\).*,\1"",g'    '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_PREFIX[ ]*=\).*,\1"./_install",g' '$(BUSYBOX_BUILD_DIR)/.config'

define DO_BUILD_LINUX
	make '$(LINUX_TARGET)'
endef

build-linux:
	rm -f '$(LINUX_TARGET)'
	$(DO_BUILD_LINUX)

build: extract $(LINUX_TARGET) $(MUSL_TARGET) $(BUSYBOX_TARGET)

$(INITRD_TARGET): $(ROOTFS_DIR)/bin/busybox
	cp -rfvTp '$(SKEL_DIR)'           '$(ROOTFS_DIR)'
	cd '$(ROOTFS_DIR)' && find . -print0 | cpio --owner 0:0 --null -ov --format=newc | gzip -9 > '$(INITRD_TARGET)'

image: build $(INITRD_TARGET)

define DO_BUILD
	make
endef

force-remove:
	rm -f $(LINUX_TARGET) $(MUSL_TARGET) $(BUSYBOX_TARGET)
	rm -f '$(INITRD_TARGET)'

image-rebuild: force-remove
	rm -rf '$(ROOTFS_DIR)'
	$(DO_BUILD)

image-repack:
	rm -f '$(INITRD_TARGET)'
	$(DO_BUILD)

net:
	-sudo ip tuntap add linux-qemu-test mode tap
	-test -x /etc/qemu-ifup && sudo /etc/qemu-ifup linux-qemu-test
	-test -x /etc/qemu-ifup || sudo scripts/qemu-ifup linux-qemu-test

qemu: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -m $(MEMORY) -vga qxl -display sdl -append='keymap=$(KEYMAP)'

qemu-console: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -m $(MEMORY) -curses -append='keymap=$(KEYMAP)'

qemu-serial: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -m $(MEMORY) -nographic -append 'console=ttyS0 keymap=$(KEYMAP)'

qemu-serial-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -m $(MEMORY) -nographic \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=linux-qemu-test,br=$(NET_BRIDGE),script=no,downscript=no -append 'net console=ttyS0 keymap=$(KEYMAP)'

qemu-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -m $(MEMORY) -vga qxl -display sdl \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=linux-qemu-test,br=$(NET_BRIDGE),script=no,downscript=no -append 'net keymap=$(KEYMAP)'

define HELP_PREFIX
	@printf '%*s%-10s - %s\n' '20' '$1' '' '$2'
endef

define HELP_PREFIX_OPTS
	@printf '%*s%-10s - %s\n' '30' '$1' '' '$2'
endef

help:
	@echo 'Available Makefile targets are:'
	$(call HELP_PREFIX,all,do all steps required for a working bzImage/initramfs)
	$(call HELP_PREFIX,pre,all pre requirements)
	$(call HELP_PREFIX,dl,download all sources)
	$(call HELP_PREFIX,extract,extract all sources)
	$(call HELP_PREFIX,build,build LinuxKernel/musl/BusyBox)
	$(call HELP_PREFIX,build-linux,force LinuxKernel rebuild)
	$(call HELP_PREFIX,force-remove,remove linux/musl/busybox and initramfs targets)
	$(call HELP_PREFIX,image,create initramfs cpio archive)
	$(call HELP_PREFIX,image-rebuild,force recreation of rootfs)
	$(call HELP_PREFIX,image-repack,force initramfs cpio archive recreation)
	$(call HELP_PREFIX,net,prepare your network bridge for use with QEMU)
	$(call HELP_PREFIX,qemu,test your kernel/initramfs combination with QEMU)
	$(call HELP_PREFIX,qemu-console,test your kernel/initramfs combination with [n]curses QEMU)
	$(call HELP_PREFIX,qemu-serial,test your kernel/initramfs combination using a serial console with QEMU)
	$(call HELP_PREFIX,qemu-serial-net,test your kernel/initramfs combination using a serial console and network support with QEMU)
	$(call HELP_PREFIX,qemu-net,test your kernel/initramfs combination with QEMU and network support through TAP)
	@echo
	@echo -e '\tAdditional make options:'
	$(call HELP_PREFIX_OPTS,NO_MODULES=y,neither build nor install kernel modules)
	$(call HELP_PREFIX_OPTS,MEMORY=[SIZE],set the RAM size for QEMU)
	$(call HELP_PREFIX_OPTS,NET_BRIDGE=[IF],set your host network bridge interface)
	$(call HELP_PREFIX_OPTS,NET_HWADDR=66:66:66:66:66:66,set mac address for the qemu guest)
	$(call HELP_PREFIX_OPTS,KEYMAP=arch/type/keymap,set a keymap which the init script tries to load)
	$(call HELP_PREFIX_OPTS,LINUX_LOCAL=/path/to/linux,set a custom linux directory)
	$(call HELP_PREFIX_OPTS,DEFCONFIG=y,use linux `make oldconfig` instead of `make x86_64_defconfig`)
	$(call HELP_PREFIX_OPTS,BUILDJOBS=[NUMBER-OF-JOBS],set the maximum number of concurrent build jobs)

.PHONY: all pre dl extract build build-linux image image-rebuild image-repack net qemu qemu-console qemu-serial qemu-serial-net qemu-net help
