################################################################################
#
# osu-lazer
#
################################################################################

# The official Linux release is an AppImage: a small ELF runtime with the
# game's squashfs appended. Its file name carries no version, so a version
# bump changes only the hash, which makes Buildroot download it again.
OSU_LAZER_VERSION = 2026.1005.0-lazer
OSU_LAZER_SITE = https://github.com/ppy/osu/releases/download/$(OSU_LAZER_VERSION)
OSU_LAZER_SOURCE = osu.AppImage
OSU_LAZER_LICENSE = MIT (game code), CC-BY-NC-4.0 (osu.Game.Resources), BASS license (proprietary, free for non-commercial use)
# The image with the game is for personal use and is not published, and
# legal-info must not collect the release as redistributable source.
OSU_LAZER_REDISTRIBUTE = NO
OSU_LAZER_EXTRACT_DEPENDENCIES = host-squashfs

# The AppImage is never executed on the build host. Its squashfs payload
# starts where the ELF runtime ends, which appimage-offset.sh reads from
# the ELF header, and unsquashfs extracts the payload from that offset.
define OSU_LAZER_EXTRACT_CMDS
	$(HOST_DIR)/bin/unsquashfs -quiet -no-progress -no-xattrs \
		-offset $$($(SHELL) $(OSU_LAZER_PKGDIR)/appimage-offset.sh \
			$(OSU_LAZER_DL_DIR)/$(OSU_LAZER_SOURCE)) \
		-dest $(@D)/appimage \
		$(OSU_LAZER_DL_DIR)/$(OSU_LAZER_SOURCE)
endef

# The AppImage's application directory (usr/bin: the osu! launcher, the
# .NET runtime, the managed assemblies and the native libraries) is
# installed as it is; /usr/bin/osukiosk-game starts it. BR2_STRIP_EXCLUDE_DIRS
# in the defconfig keeps Buildroot from stripping it. Buildroot's target
# RPATH sanitizing still rewrites the three libraries that carry one
# (libbass_fx.so, libbassmix.so, libmscordbi.so): $ORIGIN becomes
# /opt/osu-lazer, the directory they are installed in, so they resolve
# their neighbours exactly as before.
define OSU_LAZER_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/opt/osu-lazer
	cp -a $(@D)/appimage/usr/bin/. $(TARGET_DIR)/opt/osu-lazer/
endef

$(eval $(generic-package))
