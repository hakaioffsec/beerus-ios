import Foundation

enum FridaScripts {

    private static let dumpExecutable = """
    'use strict';

    const log = msg => send({ type: 'log', message: String(msg) });

    const findMainModule = () => {
        const main = Process.mainModule;
        if (main?.path.includes('.app/')) return main;

        const appModules = Process.enumerateModules().filter(m => m.path.includes('.app/'));
        return appModules.find(m => {
            const appFolder = m.path.split('/').find(p => p.includes('.app'))?.replace('.app', '');
            return m.name === appFolder;
        }) || main;
    };

    const parseMachO = base => {
        const magic = base.readU32();
        if (magic !== 0xfeedfacf) throw new Error('Only 64-bit binaries supported');

        const ncmds = base.add(16).readU32();
        const LC_SEGMENT_64 = 0x19, LC_ENCRYPTION_INFO_64 = 0x2C;

        let segments = [], cryptIdOffset = 0, textVm = null;
        let offset = 32;

        for (let i = 0; i < ncmds; i++) {
            const cmd = base.add(offset).readU32();
            const size = base.add(offset + 4).readU32();

            if (cmd === LC_SEGMENT_64) {
                const name = base.add(offset + 8).readUtf8String();
                const vmaddr = base.add(offset + 24).readU64().toNumber();
                const fileoff = base.add(offset + 40).readU64().toNumber();
                const filesize = base.add(offset + 48).readU64().toNumber();

                if (name === '__TEXT') {
                    textVm = vmaddr;
                    log(`Found __TEXT at 0x${vmaddr.toString(16)}`);
                }
                if (filesize > 0) segments.push({ name, vmaddr, fileoff, filesize });
            }

            if (cmd === LC_ENCRYPTION_INFO_64) {
                cryptIdOffset = offset + 16;
                log(`Found LC_ENCRYPTION_INFO_64, cryptid=${base.add(cryptIdOffset).readU32()}`);
            }

            offset += size;
        }

        if (textVm === null) throw new Error('__TEXT segment not found');
        log(`Parsed ${segments.length} segments`);

        return { segments, cryptIdOffset, textVm };
    };

    const getBundleInfo = module => {
        let bundlePath = '', appName = module.name;

        if (typeof ObjC !== 'undefined' && ObjC.available) {
            try {
                const bundle = ObjC.classes.NSBundle.mainBundle();
                const info = bundle.infoDictionary();
                appName = (info.objectForKey_('CFBundleDisplayName') ||
                          info.objectForKey_('CFBundleName') ||
                          module.name).toString();
                bundlePath = bundle.bundlePath().toString();
            } catch(e) {}
        }

        if (!bundlePath) bundlePath = module.path.split('.app')[0] + '.app';
        return { bundlePath, appName };
    };

    const dumpExecutable = outputPath => {
        log('Starting dump...');
        const module = findMainModule();
        if (!module) throw new Error('Main module not found');

        log(`Module: ${module.path}`);
        const { segments, cryptIdOffset, textVm } = parseMachO(module.base);

        const file = new File(outputPath, 'wb');
        segments.forEach(seg => {
            log(`Dumping ${seg.name}`);
            const addr = module.base.add(seg.vmaddr - textVm);
            file.seek(seg.fileoff);
            file.write(addr.readByteArray(seg.filesize));
        });

        if (cryptIdOffset) {
            log('Zeroing cryptid');
            file.seek(cryptIdOffset);
            file.write(new Uint8Array(4).buffer);
        }
        file.close();

        const { bundlePath, appName } = getBundleInfo(module);
        log('Dump complete');

        return {
            success: true,
            path: outputPath,
            bundlePath,
            executableName: module.name,
            appName
        };
    };
    """

    static func dumpScript(outputPath: String) -> String {
        dumpExecutable + """

        (function() {
            try {
                send({ type: 'result', data: dumpExecutable('\(outputPath)') });
            } catch (e) {
                log('Error: ' + e.message);
                send({ type: 'error', message: e.message });
            }
        })();
        """
    }

    // MARK: - Memory Dump Script

    private static let memoryDumpScript = """
    'use strict';

    const log = msg => send({ type: 'log', message: String(msg) });

    const dumpMemory = (outputDir) => {
        log('Enumerating memory...');
        const ranges = Process.enumerateRanges('r--');
        const modules = Process.enumerateModules();

        // Filter: skip frida, skip < 4KB, skip > 16MB
        const filtered = [];
        let totalBytes = 0;
        for (const r of ranges) {
            if (r.size < 4096 || r.size > 16777216) continue;
            if (r.file && r.file.path) {
                const lp = r.file.path.toLowerCase();
                if (lp.includes('frida') || lp.includes('gum') || lp.includes('substrate') || lp.includes('substitute')) continue;
            }
            filtered.push(r);
            totalBytes += r.size;
        }

        log(filtered.length + ' ranges (' + (totalBytes / 1048576).toFixed(1) + ' MB)');

        // Single binary output — no per-range file overhead
        const file = new File(outputDir + '/dump.bin', 'wb');
        const entries = [];
        let offset = 0;
        let dumpedCount = 0;
        let dumpedBytes = 0;
        let errorCount = 0;

        for (let i = 0; i < filtered.length; i++) {
            const r = filtered[i];
            try {
                // Read in 1MB chunks to keep Frida responsive
                const CHUNK = 1048576;
                let wrote = 0;
                while (wrote < r.size) {
                    const len = Math.min(CHUNK, r.size - wrote);
                    const data = r.base.add(wrote).readByteArray(len);
                    if (data === null) break;
                    file.write(data);
                    wrote += len;
                }
                if (wrote <= 0) { errorCount++; continue; }

                entries.push({
                    o: offset,
                    s: wrote,
                    b: r.base.toString(),
                    p: r.protection,
                    f: r.file ? r.file.path : null,
                });
                offset += wrote;
                dumpedCount++;
                dumpedBytes += wrote;

                if (dumpedCount % 20 === 0) {
                    log(dumpedCount + '/' + filtered.length +
                        ' (' + (dumpedBytes / 1048576).toFixed(1) + ' MB)');
                }
            } catch (e) {
                errorCount++;
            }
        }
        file.close();

        // Compact index
        const idx = new File(outputDir + '/index.json', 'w');
        idx.write(JSON.stringify({
            proc: {
                pid: Process.id,
                arch: Process.arch,
                ptr: Process.pointerSize,
                main: Process.mainModule ? Process.mainModule.path : null,
            },
            mods: modules.map(m => [m.name, m.base.toString(), m.size, m.path]),
            ranges: entries,
            stat: { total: ranges.length, dumped: dumpedCount, bytes: dumpedBytes, err: errorCount },
        }));
        idx.close();

        log('Done: ' + dumpedCount + ' ranges, ' + (dumpedBytes / 1048576).toFixed(1) + ' MB');

        return {
            success: true,
            dumpedRanges: dumpedCount,
            totalRanges: ranges.length,
            dumpedBytes: dumpedBytes,
            errors: errorCount,
        };
    };
    """

    static func memoryDumpScript(outputDir: String) -> String {
        memoryDumpScript + """

        (function() {
            try {
                send({ type: 'result', data: dumpMemory('\(outputDir)') });
            } catch (e) {
                log('Error: ' + e.message);
                send({ type: 'error', message: e.message });
            }
        })();
        """
    }

}
