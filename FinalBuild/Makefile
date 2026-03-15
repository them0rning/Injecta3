export THEOS ?= /opt/theos
export TARGET := iphone:clang:16.5:15.0
export ARCHS  := arm64
export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# ── Tweak ──────────────────────────────────────────────────────────────────
TWEAK_NAME = CameraInject
CameraInject_FILES      = Tweak.xm SampleBufferFactory.mm
CameraInject_FRAMEWORKS = AVFoundation CoreMedia CoreVideo UIKit Foundation CoreFoundation
CameraInject_CFLAGS     = -fobjc-arc -I$(THEOS_PROJECT_DIR)/include
CameraInject_CCFLAGS    = -fobjc-arc -std=c++17
CameraInject_LDFLAGS    = -lsubstrate

include $(THEOS)/makefiles/tweak.mk

# ── Companion App ──────────────────────────────────────────────────────────
APPLICATION_NAME = CameraInjectApp
CameraInjectApp_FILES        = App/AppDelegate.m App/MainViewController.m
CameraInjectApp_FRAMEWORKS   = UIKit Foundation CoreGraphics CoreFoundation
CameraInjectApp_CFLAGS       = -fobjc-arc
CameraInjectApp_INSTALL_PATH = /Applications
CameraInjectApp_DISPLAY_NAME = CamInject

include $(THEOS)/makefiles/application.mk

after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/var/jb/Library/CameraInject
