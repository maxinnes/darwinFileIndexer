THEOS_DEVICE_IP = 127.0.0.1
THEOS_DEVICE_PORT = 2222

GO_EASY_ON_ME = 1

TARGET := iphone:clang:latest:7.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = dfi

dfi_FILES = main.m
dfi_CFLAGS = -fobjc-arc
dfi_CODESIGN_FLAGS = -Sentitlements.plist
dfi_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
