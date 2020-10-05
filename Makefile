ARCH=$(shell uname -m)
MEMORY ?= 128
NET_QEMU_TAP ?= linux-qemu-test
NET_BRIDGE ?= br0
NET_HWADDR ?= 66:66:66:66:66:66
KEYMAP ?= i386/qwertz/de-latin1
LINUX_LOCAL ?=
DEFCONFIG ?= n
NO_MODULES ?= n
USE_GDB ?= n

BUILDJOBS ?= $(shell cat /proc/cpuinfo | grep -o '^processor' | wc -l)
THIS_DIR=$(realpath .)

DL_DIR=$(THIS_DIR)/dl
BUILD_DIR=$(THIS_DIR)/build
ROOTFS_DIR=$(THIS_DIR)/rootfs
CFG_DIR=$(THIS_DIR)/config
SCRIPT_DIR=$(THIS_DIR)/scripts
SKEL_DIR=$(THIS_DIR)/skeleton

INITRD_TARGET=$(THIS_DIR)/initramfs.cpio.gz

LINUX_DL_PREFIX=https://cdn.kernel.org/pub/linux/kernel/v5.x
LINUX_DL_BASENAME=linux
LINUX_DL_VERSION=5.8.8
LINUX_DL_SUFFIX=tar.xz
LINUX_DL_URL=$(LINUX_DL_PREFIX)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_DL_FILE=$(DL_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_BUILD_DIR=$(BUILD_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION)
LINUX_TARGET=$(LINUX_BUILD_DIR)/vmlinux
LINUX_INSTALL_PREFIX=$(ROOTFS_DIR)/usr
LINUX_INSTALLED_MODULES=$(LINUX_INSTALL_PREFIX)/lib/modules
LINUX_INSTALLED_HEADERS=$(LINUX_INSTALL_PREFIX)/include/linux

MUSL_DL_PREFIX=https://www.musl-libc.org/releases
MUSL_DL_BASENAME=musl
MUSL_DL_VERSION=1.2.1
MUSL_DL_SUFFIX=tar.gz
MUSL_DL_URL=$(MUSL_DL_PREFIX)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_DL_FILE=$(DL_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_BUILD_DIR=$(BUILD_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)
MUSL_TARGET=$(MUSL_BUILD_DIR)/lib/libc.so

BUSYBOX_DL_PREFIX=https://busybox.net/downloads
BUSYBOX_DL_BASENAME=busybox
BUSYBOX_DL_VERSION=1.31.0
BUSYBOX_DL_SUFFIX=tar.bz2
BUSYBOX_DL_URL=$(BUSYBOX_DL_PREFIX)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_DL_FILE=$(DL_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_BUILD_DIR=$(BUILD_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION)
BUSYBOX_CFLAGS=-I'$(ROOTFS_DIR)/usr/include' -specs '$(MUSL_BUILD_DIR)/lib/musl-gcc.specs'
BUSYBOX_LDFLAGS=-L$(ROOTFS_DIR)/lib
BUSYBOX_TARGET=$(BUSYBOX_BUILD_DIR)/busybox

all: pre dl extract build image
	@echo 'Finished.'

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
ifeq ($(LINUX_LOCAL),)
	wget '$(LINUX_DL_URL)' -O '$@' || (rm -f '$(LINUX_DL_FILE)' && false)
endif

$(MUSL_DL_FILE):
	wget '$(MUSL_DL_URL)' -O '$@' || (rm -f '$(MUSL_DL_FILE)' && false)

$(BUSYBOX_DL_FILE):
	wget '$(BUSYBOX_DL_URL)' -O '$@' || (rm -f '$(BUSYBOX_DL_FILE)' && false)

dl: pre $(LINUX_DL_FILE) $(MUSL_DL_FILE) $(BUSYBOX_DL_FILE)

$(LINUX_BUILD_DIR)/Makefile:
ifeq ($(LINUX_LOCAL),)
	tar --strip-components=1 -C '$(LINUX_BUILD_DIR)' -xvf '$(LINUX_DL_FILE)' >/dev/null || (rm -rf '$(LINUX_BUILD_DIR)' && false)
else
	rmdir '$(LINUX_BUILD_DIR)'
	ln -s '$(LINUX_LOCAL)' '$(LINUX_BUILD_DIR)'
endif

$(MUSL_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(MUSL_BUILD_DIR)' -xvzf '$(MUSL_DL_FILE)' >/dev/null || (rm -rf '$(MUSL_BUILD_DIR)' && false)

$(BUSYBOX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(BUSYBOX_BUILD_DIR)' -xvjf '$(BUSYBOX_DL_FILE)' >/dev/null || (rm -rf '$(BUSYBOX_BUILD_DIR)' && false)

extract: dl $(LINUX_BUILD_DIR)/Makefile $(MUSL_BUILD_DIR)/Makefile $(BUSYBOX_BUILD_DIR)/Makefile

$(LINUX_TARGET):
	cp -v '$(CFG_DIR)/linux.config' '$(LINUX_BUILD_DIR)/.config'
ifneq ($(DEFCONFIG),y)
	make -C '$(LINUX_BUILD_DIR)' oldconfig
else
	make -C '$(LINUX_BUILD_DIR)' x86_64_defconfig
endif
	-make -C '$(LINUX_BUILD_DIR)' kvmconfig
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' bzImage

$(LINUX_INSTALLED_MODULES): $(LINUX_TARGET)
ifneq ($(NO_MODULES),y)
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules_install
endif

$(LINUX_INSTALLED_HEADERS): $(LINUX_TARGET)
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_HDR_PATH='$(ROOTFS_DIR)/usr' headers_install

$(MUSL_TARGET): $(LINUX_INSTALLED_HEADERS)
	rm -f $(MUSL_TARGET)
	cd '$(MUSL_BUILD_DIR)' && (test -r ./config.mak || ./configure --prefix='$(ROOTFS_DIR)/usr' --enable-wrapper=yes)
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install
	test -e '$(ROOTFS_DIR)/lib' || ln -sr '$(ROOTFS_DIR)/usr/lib' '$(ROOTFS_DIR)/lib'
	test -e '$(ROOTFS_DIR)/lib/ld-musl-$(ARCH).so.1' || ln -sr '$(ROOTFS_DIR)/lib/libc.so' '$(ROOTFS_DIR)/lib/ld-musl-$(ARCH).so.1'
	rm '$(ROOTFS_DIR)/usr/bin/musl-gcc' '$(ROOTFS_DIR)/lib/musl-gcc.specs'

$(BUSYBOX_TARGET): $(MUSL_TARGET) $(LINUX_INSTALLED_HEADERS)
	cp -v '$(CFG_DIR)/busybox.config' '$(BUSYBOX_BUILD_DIR)/.config'
ifneq ($(DEFCONFIG),y)
	make -C '$(BUSYBOX_BUILD_DIR)' oldconfig
else
	make -C '$(BUSYBOX_BUILD_DIR)' defconfig
endif
	test -r '$(MUSL_BUILD_DIR)/lib/musl-gcc.specs'
	sed -i 's,^\(CONFIG_EXTRA_CFLAGS[ ]*=\).*,\1"$(BUSYBOX_CFLAGS)",g'   '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_LDFLAGS[ ]*=\).*,\1"$(BUSYBOX_LDFLAGS)",g' '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_PREFIX[ ]*=\).*,\1"$(ROOTFS_DIR)",g'             '$(BUSYBOX_BUILD_DIR)/.config'
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install

build: extract $(LINUX_TARGET) $(LINUX_INSTALLED_MODULES) $(MUSL_TARGET) $(BUSYBOX_TARGET)

$(INITRD_TARGET): $(LINUX_TARGET) $(LINUX_INSTALLED_MODULES) $(MUSL_TARGET) $(BUSYBOX_TARGET)
	cp -rfvTp '$(SKEL_DIR)'           '$(ROOTFS_DIR)'
	cd '$(ROOTFS_DIR)' && find . -print0 | cpio --owner 0:0 --null -ov --format=newc | gzip -9 > '$(INITRD_TARGET)'

image: build $(INITRD_TARGET)

define DO_BUILD
	make
endef

force-remove:
	rm -f $(LINUX_TARGET) $(MUSL_TARGET) $(BUSYBOX_TARGET)
	rm -rf $(LINUX_INSTALLED_HEADERS) $(LINUX_INSTALLED_MODULES)
	rm -f '$(INITRD_TARGET)'

image-rebuild: force-remove
	rm -rf '$(ROOTFS_DIR)'
	$(DO_BUILD)

image-repack:
	rm -f '$(INITRD_TARGET)'
	$(DO_BUILD)

net:
	sudo ip tuntap add $(NET_QEMU_TAP) mode tap
	sudo ip link set dev $(NET_QEMU_TAP) up
	sudo ip link set dev $(NET_QEMU_TAP) master $(NET_BRIDGE)

net-clean:
	sudo ip link delete $(NET_QEMU_TAP)

ifeq ($(USE_GDB),y)
QEMU_ARGS += -s -S
endif

qemu-gdb-connect:
	gdb -s '$(LINUX_BUILD_DIR)/vmlinux' -x ./qemu-gdb.cmds

qemu: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' \
		-enable-kvm -m $(MEMORY) -vga qxl -display sdl \
		-append 'nokaslr keymap=$(KEYMAP)' $(QEMU_ARGS)

qemu-console: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' \
		-enable-kvm -m $(MEMORY) -curses \
		-append 'nokaslr keymap=$(KEYMAP)' $(QEMU_ARGS)

qemu-serial: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' \
		-enable-kvm -m $(MEMORY) -nographic \
		-append 'nokaslr console=ttyS0 keymap=$(KEYMAP)' $(QEMU_ARGS)

qemu-serial-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' \
		-enable-kvm -m $(MEMORY) -nographic \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=$(NET_QEMU_TAP),br=$(NET_BRIDGE),script=no,downscript=no \
		-append 'nokaslr net console=ttyS0 keymap=$(KEYMAP)' \
		$(QEMU_ARGS)

qemu-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' \
		-enable-kvm -m $(MEMORY) -vga qxl -display sdl \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=$(NET_QEMU_TAP),br=$(NET_BRIDGE),script=no,downscript=no \
		-append 'nokaslr net keymap=$(KEYMAP)' $(QEMU_ARGS)

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
	$(call HELP_PREFIX_OPTS,USE_GDB=$(USE_GDB),start QEMU with debugging capabilities enabled)
	$(call HELP_PREFIX_OPTS,NO_MODULES=$(NO_MODULES),neither build nor install kernel modules)
	$(call HELP_PREFIX_OPTS,MEMORY=$(MEMORY),set the RAM size for QEMU in MBytes)
	$(call HELP_PREFIX_OPTS,NET_QEMU_TAP=$(NET_QEMU_TAP),set the ifname which QEMU will use as TAP device (run `make net` before))
	$(call HELP_PREFIX_OPTS,NET_BRIDGE=$(NET_BRIDGE),set your host network bridge interface)
	$(call HELP_PREFIX_OPTS,NET_HWADDR=$(NET_HWADDR),set mac address for the qemu guest)
	$(call HELP_PREFIX_OPTS,KEYMAP=$(KEYMAP),set a keymap which the init script tries to load)
	$(call HELP_PREFIX_OPTS,LINUX_LOCAL=$(LINUX_LOCAL),set a custom linux source directory)
	$(call HELP_PREFIX_OPTS,DEFCONFIG=$(DEFCONFIG),use linux `make $(DEFCONFIG_NAME)` instead of `make oldconfig`)
	$(call HELP_PREFIX_OPTS,BUILDJOBS=$(BUILDJOBS),set the maximum number of concurrent build jobs)

.PHONY: all pre dl extract build image image-rebuild image-repack net qemu qemu-console qemu-serial qemu-serial-net qemu-net help
