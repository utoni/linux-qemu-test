BUILDJOBS ?= 5
THIS_DIR=$(realpath .)

DL_DIR=$(THIS_DIR)/dl
BUILD_DIR=$(THIS_DIR)/build

ROOT_DIR=$(THIS_DIR)/root
STAGING_DIR=$(THIS_DIR)/staging

LINUX_DL_PREFIX=https://cdn.kernel.org/pub/linux/kernel/v4.x
LINUX_DL_BASENAME=linux
LINUX_DL_VERSION=4.18
LINUX_DL_SUFFIX=tar.xz
LINUX_DL_URL=$(LINUX_DL_PREFIX)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_DL_FILE=$(DL_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_BUILD_DIR=$(BUILD_DIR)/linux-$(LINUX_DL_VERSION)

all: pre dl extract build

pre:
	mkdir -p $(DL_DIR)
	mkdir -p $(BUILD_DIR)
	mkdir -p $(LINUX_BUILD_DIR)

$(LINUX_DL_FILE):
	wget '$(LINUX_DL_URL)' -O '$@' || (rm -f '$(LINUX_DL_FILE)' && false)

dl: pre $(LINUX_DL_FILE)

$(LINUX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(LINUX_BUILD_DIR)' -xvf '$(LINUX_DL_FILE)' || (rm -rf '$(LINUX_BUILD_DIR)' && false)

extract: dl $(LINUX_BUILD_DIR)/Makefile

$(LINUX_BUILD_DIR)/vmlinux:
	make -C '$(LINUX_BUILD_DIR)' allnoconfig
	echo 'CONFIG_64BIT=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_BLK_DEV_INITRD=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_EXPERT=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_BINFMT_ELF=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_BINFMT_SCRIPT=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_DEVTMPFS=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_DEVTMPFS_MOUNT=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_TTY=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_VT=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_VT_CONSOLE=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_SERIAL_8250=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_SERIAL_8250_CONSOLE=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_PROC_FS=y' >>'$(LINUX_BUILD_DIR)/.config'
	echo 'CONFIG_SYSFS=y' >>'$(LINUX_BUILD_DIR)/.config'
	make -C '$(LINUX_BUILD_DIR)' menuconfig
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS)

build: extract $(LINUX_BUILD_DIR)/vmlinux
