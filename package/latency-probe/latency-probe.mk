################################################################################
#
# latency-probe
#
################################################################################

# The source lives in this repository, hence the local site method:
# Buildroot rsyncs the directory into its build tree, so after editing the
# source run "make latency-probe-rebuild" to pick the change up.
LATENCY_PROBE_SITE = $(BR2_EXTERNAL_OSUKIOSK_PATH)/src/latency-probe
LATENCY_PROBE_SITE_METHOD = local
LATENCY_PROBE_DEPENDENCIES = host-pkgconf host-wayland wayland wayland-protocols

# TARGET_CONFIGURE_OPTS brings CC, CFLAGS, LDFLAGS and PKG_CONFIG for the
# target. The scanner has to be the host one and the protocol XML comes
# from staging, so both are passed explicitly.
define LATENCY_PROBE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) \
		WAYLAND_SCANNER=$(HOST_DIR)/bin/wayland-scanner \
		WAYLAND_PROTOCOLS_DIR=$(STAGING_DIR)/usr/share/wayland-protocols
endef

define LATENCY_PROBE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/latency-probe $(TARGET_DIR)/usr/bin/latency-probe
	$(INSTALL) -D -m 0755 $(@D)/latency-probe-vt $(TARGET_DIR)/usr/bin/latency-probe-vt
endef

$(eval $(generic-package))
