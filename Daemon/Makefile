CC = clang
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
CFLAGS = -arch arm64 -isysroot $(SDK) -miphoneos-version-min=14.0 -O2 -Wall
LIBS = -lproc

all: beerusd

beerusd: BeerusDaemon.c
	$(CC) $(CFLAGS) $(LIBS) -o $@ $<
	ldid -S $@

clean:
	rm -f beerusd

install:
	@echo "scp beerusd root@<device>:/usr/local/bin/"
	@echo "scp com.beerus.daemon.plist root@<device>:/Library/LaunchDaemons/"
	@echo "ssh root@<device> 'chmod 755 /usr/local/bin/beerusd'"
	@echo "ssh root@<device> 'launchctl load /Library/LaunchDaemons/com.beerus.daemon.plist'"
