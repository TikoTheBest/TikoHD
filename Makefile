# TikoHD — forces TikTok iOS to publish in true 1080p60 HD.
# Builds a Substrate tweak dylib you inject into a stock TikTok IPA (pyzule/azule).

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikoHD
TikoHD_FILES = Tweak.x
TikoHD_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
TikoHD_FRAMEWORKS = UIKit Foundation AVFoundation

# TikTok's process name inside the app bundle is "TikTok"
INSTALL_TARGET_PROCESSES = TikTok

include $(THEOS)/makefiles/tweak.mk
