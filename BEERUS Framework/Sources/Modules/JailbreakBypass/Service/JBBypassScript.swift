import Foundation

enum JBBypassScript {
    // ponytail: whitelist approach, only blocks known paths, fails open on any error
    static let source = """
    'use strict';

    (function() {
        const JB_PATHS = new Set([
            '/Applications/Cydia.app', '/Applications/Sileo.app', '/Applications/Zebra.app',
            '/Applications/Filza.app', '/Applications/NewTerm.app', '/var/jb',
            '/.installed_unc0ver', '/.installed_taurine', '/.installed_palera1n',
            '/.installed_dopamine', '/.installed_chimera', '/.installed_electra',
            '/Library/MobileSubstrate', '/usr/lib/libsubstrate.dylib', '/usr/lib/libhooker.dylib',
            '/usr/lib/substitute-loader.dylib', '/var/lib/dpkg', '/var/lib/apt', '/etc/apt',
            '/usr/sbin/frida-server', '/usr/bin/cycript', '/usr/bin/ssh', '/bin/bash',
            '/usr/bin/sshd', '/etc/ssh/sshd_config', '/private/var/lib/apt',
            '/private/var/lib/dpkg', '/private/var/stash', '/private/var/tmp/cydia.log',
            '/var/cache/apt', '/var/log/syslog', '/bin/sh', '/usr/libexec/sftp-server',
            '/usr/libexec/ssh-keysign', '/Library/PreferenceBundles', '/Library/PreferenceLoader',
            '/Library/Themes', '/Library/dpkg', '/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist',
            '/private/var/jb', '/usr/lib/libellekit.dylib', '/var/jb/usr/lib/libellekit.dylib'
        ]);

        const JB_PREFIXES = ['/var/jb/', '/private/var/jb/', '/Library/MobileSubstrate/', '/var/lib/dpkg/', '/var/lib/apt/', '/usr/lib/frida/'];
        const JB_SUBSTRINGS = ['frida', 'cycript', 'substrate', 'substitute', 'libhooker', 'cynject', 'tweakinject', 'ellekit'];
        const JB_SCHEMES = ['cydia', 'sileo', 'zebra', 'filza', 'activator'];
        const JB_ENVS = ['DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', '_MSSafeMode', 'SUBSTRATE_HOME'];

        const isJBPath = (path) => {
            if (!path) return false;
            const p = path.toString();
            if (JB_PATHS.has(p)) return true;
            for (const prefix of JB_PREFIXES) if (p.startsWith(prefix)) return true;
            const lower = p.toLowerCase();
            for (const sub of JB_SUBSTRINGS) if (lower.includes(sub)) return true;
            return false;
        };

        // ponytail: hook C functions with fail-open pattern
        const hookC = (name, onEnter) => {
            try {
                const fn = Module.findExportByName(null, name);
                if (!fn) return;
                Interceptor.attach(fn, {
                    onEnter: function(args) {
                        try { onEnter.call(this, args); } catch(e) { /* fail open */ }
                    },
                    onLeave: function(retval) {
                        if (this.blocked) retval.replace(ptr(-1));
                    }
                });
            } catch(e) { /* skip this hook */ }
        };

        // stat family
        ['stat', 'lstat', 'stat64', 'lstat64'].forEach(fn => {
            hookC(fn, function(args) {
                const path = args[0].readUtf8String();
                if (isJBPath(path)) this.blocked = true;
            });
        });

        // access
        hookC('access', function(args) {
            const path = args[0].readUtf8String();
            if (isJBPath(path)) this.blocked = true;
        });

        // open
        hookC('open', function(args) {
            const path = args[0].readUtf8String();
            if (isJBPath(path)) this.blocked = true;
        });

        // fopen - return NULL instead of -1
        try {
            const fopen = Module.findExportByName(null, 'fopen');
            if (fopen) {
                Interceptor.attach(fopen, {
                    onEnter(args) {
                        try {
                            const path = args[0].readUtf8String();
                            if (isJBPath(path)) this.returnNull = true;
                        } catch(e) {}
                    },
                    onLeave(retval) {
                        if (this.returnNull) retval.replace(ptr(0));
                    }
                });
            }
        } catch(e) {}

        // getenv
        try {
            Interceptor.attach(Module.findExportByName(null, 'getenv'), {
                onEnter(args) { this.name = args[0].readUtf8String(); },
                onLeave(retval) {
                    if (JB_ENVS.includes(this.name)) retval.replace(ptr(0));
                }
            });
        } catch(e) {}

        // fork - always fail (sandbox behavior)
        try {
            Interceptor.replace(Module.findExportByName(null, 'fork'),
                new NativeCallback(() => -1, 'int', []));
        } catch(e) {}

        // ObjC hooks
        if (ObjC.available) {
            // NSFileManager
            try {
                const fm = ObjC.classes.NSFileManager;
                ['- fileExistsAtPath:', '- fileExistsAtPath:isDirectory:'].forEach(sel => {
                    if (!fm[sel]) return;
                    Interceptor.attach(fm[sel].implementation, {
                        onEnter(args) {
                            try { this.path = ObjC.Object(args[2]).toString(); } catch(e) { this.path = ''; }
                        },
                        onLeave(retval) {
                            if (isJBPath(this.path)) retval.replace(ptr(0));
                        }
                    });
                });
            } catch(e) {}

            // UIApplication canOpenURL
            try {
                const uiapp = ObjC.classes.UIApplication;
                if (uiapp && uiapp['- canOpenURL:']) {
                    Interceptor.attach(uiapp['- canOpenURL:'].implementation, {
                        onEnter(args) {
                            try {
                                const url = ObjC.Object(args[2]);
                                this.scheme = url.scheme ? url.scheme().toString().toLowerCase() : '';
                            } catch(e) { this.scheme = ''; }
                        },
                        onLeave(retval) {
                            if (JB_SCHEMES.includes(this.scheme)) retval.replace(ptr(0));
                        }
                    });
                }
            } catch(e) {}

            // NSProcessInfo environment
            try {
                const procInfo = ObjC.classes.NSProcessInfo;
                if (procInfo && procInfo['- environment']) {
                    Interceptor.attach(procInfo['- environment'].implementation, {
                        onLeave(retval) {
                            try {
                                const env = ObjC.Object(retval);
                                const mutable = env.mutableCopy();
                                JB_ENVS.forEach(k => mutable.removeObjectForKey_(k));
                                retval.replace(mutable.handle);
                            } catch(e) {}
                        }
                    });
                }
            } catch(e) {}
        }

        // dyld image filtering
        try {
            const realCount = new NativeFunction(Module.findExportByName(null, '_dyld_image_count'), 'uint32', []);
            const realName = new NativeFunction(Module.findExportByName(null, '_dyld_get_image_name'), 'pointer', ['uint32']);

            const filtered = [];
            for (let i = 0; i < realCount(); i++) {
                const namePtr = realName(i);
                if (namePtr.isNull()) continue;
                const name = namePtr.readUtf8String();
                const lower = name ? name.toLowerCase() : '';
                let isJB = false;
                for (const sub of JB_SUBSTRINGS) {
                    if (lower.includes(sub)) { isJB = true; break; }
                }
                if (!isJB) filtered.push(i);
            }

            Interceptor.replace(Module.findExportByName(null, '_dyld_image_count'),
                new NativeCallback(() => filtered.length, 'uint32', []));
            Interceptor.replace(Module.findExportByName(null, '_dyld_get_image_name'),
                new NativeCallback((idx) => {
                    if (idx >= 0 && idx < filtered.length) return realName(filtered[idx]);
                    return ptr(0);
                }, 'pointer', ['uint32']));
        } catch(e) {}

        send({ type: 'log', message: '[beerus] JB bypass hooks installed' });
    })();
    """
}
