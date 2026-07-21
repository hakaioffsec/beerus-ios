# BeerusJBBypass - Standalone dylib build (no Theos)
# Uses fishhook for C hooks + ObjC runtime for method swizzling

SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC = $(shell xcrun --sdk iphoneos -f clang)
LDID = ldid

ARCH = arm64
MIN_IOS = 15.0

CFLAGS = -arch $(ARCH) \
         -isysroot $(SDK) \
         -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc \
         -Wno-deprecated-declarations \
         -O2

LDFLAGS = -arch $(ARCH) \
          -isysroot $(SDK) \
          -miphoneos-version-min=$(MIN_IOS) \
          -dynamiclib \
          -install_name /var/jb/Library/TweakInject/BeerusJBBypass.dylib \
          -framework Foundation \
          -framework UIKit

TARGET = BeerusJBBypass.dylib
SOURCES = BeerusJBBypass.m fishhook.c
OBJECTS = BeerusJBBypass.o fishhook.o

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $(OBJECTS)
	$(LDID) -S $@
	@echo "Built: $(TARGET)"

BeerusJBBypass.o: BeerusJBBypass.m fishhook.h
	$(CC) $(CFLAGS) -c BeerusJBBypass.m -o $@

fishhook.o: fishhook.c fishhook.h
	$(CC) $(CFLAGS) -c fishhook.c -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

install: $(TARGET)
	@echo "Installing to device..."
	sshpass -p alpine ssh -p 2222 root@127.0.0.1 'mkdir -p /var/jb/usr/lib/TweakInject' 2>/dev/null || true
	sshpass -p alpine scp -P 2222 $(TARGET) BeerusJBBypass.plist root@127.0.0.1:/var/jb/usr/lib/TweakInject/
	@echo "Installed to /var/jb/usr/lib/TweakInject/. Respring to activate."

.PHONY: all clean install
