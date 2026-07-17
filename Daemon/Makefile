CC = clang
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
CFLAGS = -arch arm64 -isysroot $(SDK) -miphoneos-version-min=14.0 -O2 -Wall
LIBS = -lproc
FRAMEWORKS = -framework CoreFoundation

all: beerusd

beerusd: BeerusDaemon.c BeerusInjector.c MachOPatcher.c
	$(CC) $(CFLAGS) $(LIBS) $(FRAMEWORKS) -o $@ BeerusDaemon.c BeerusInjector.c MachOPatcher.c
	ldid -Sent.plist $@

clean:
	rm -f beerusd

install:
	@echo "=== Rootful install ==="
	@echo "scp beerusd root@<device>:/usr/local/bin/"
	@echo "scp com.beerus.daemon.plist root@<device>:/Library/LaunchDaemons/"
	@echo ""
	@echo "=== Rootless install ==="
	@echo "scp beerusd root@<device>:/var/jb/usr/local/bin/"
	@echo "scp com.beerus.daemon.plist root@<device>:/var/jb/Library/LaunchDaemons/"
	@echo ""
	@echo "=== Then on device ==="
	@echo "chmod 755 <path>/usr/local/bin/beerusd"
	@echo "launchctl bootstrap system <path>/Library/LaunchDaemons/com.beerus.daemon.plist"
