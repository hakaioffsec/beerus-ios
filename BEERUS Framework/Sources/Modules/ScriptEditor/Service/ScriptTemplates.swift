import Foundation

enum ScriptTemplates {

    /// Central list — used by seed and template picker.
    static let all: [(name: String, source: String)] = [
        ("Hook ObjC Method",   hookObjCMethod),
        ("Trace All Methods",  traceAllMethods),
        ("SSL Pinning Bypass", sslPinningBypass),
        ("List Classes",       listClasses),
        ("Intercept Network",  interceptNetwork),
        ("Keychain Dump",      keychainDump),
    ]

    static let hookObjCMethod = """
    // Hook an Objective-C method
    // Replace ClassName and methodName: with your targets

    var target = ObjC.classes.ClassName;
    var methodName = "- methodName:";

    Interceptor.attach(target[methodName].implementation, {
        onEnter: function(args) {
            console.log("[*] Called " + methodName);
            console.log("    self: " + ObjC.Object(args[0]));
            console.log("    _cmd: " + ObjC.selectorAsString(args[1]));
            console.log("    arg1: " + ObjC.Object(args[2]));
        },
        onLeave: function(retval) {
            console.log("    retval: " + retval);
        }
    });
    """

    static let traceAllMethods = """
    // Trace all methods of a class
    // Replace "TargetClass" with the class you want to trace

    var className = "TargetClass";
    var methods = ObjC.classes[className].$ownMethods;

    console.log("[*] Tracing " + methods.length + " methods on " + className);

    methods.forEach(function(method) {
        try {
            Interceptor.attach(ObjC.classes[className][method].implementation, {
                onEnter: function(args) {
                    console.log("[TRACE] " + className + " " + method);
                }
            });
        } catch(e) {
            console.log("[!] Could not trace: " + method + " — " + e);
        }
    });

    console.log("[*] Tracing active");
    """

    static let sslPinningBypass = """
    // SSL Pinning Bypass — covers common frameworks
    // Works with NSURLSession, AFNetworking, TrustKit, Alamofire

    try {
        var resolver = new ApiResolver("objc");

        // NSURLSession delegate
        resolver.enumerateMatches(
            "-[* URLSession:didReceiveChallenge:completionHandler:]",
            { onMatch: function(match) {
                Interceptor.attach(match.address, {
                    onEnter: function(args) {
                        var dominated = new ObjC.Block(args[4]);
                        dominated.implementation = function(disp, cred) {
                            var challenge = ObjC.Object(args[3]);
                            var trust = challenge.protectionSpace().serverTrust();
                            var credential = ObjC.classes.NSURLCredential
                                .credentialForTrust_(trust);
                            dominated.implementation(0, credential);
                        };
                    }
                });
                console.log("[SSL] Hooked: " + match.name);
            }}
        );

        // TrustKit
        if (ObjC.classes.TSKPinningValidator) {
            var m = ObjC.classes.TSKPinningValidator["- evaluateTrust:forHostname:"];
            if (m) {
                Interceptor.attach(m.implementation, {
                    onLeave: function(retval) { retval.replace(0); }
                });
                console.log("[SSL] TrustKit bypassed");
            }
        }

        console.log("[SSL] Pinning bypass active");
    } catch(e) {
        console.log("[SSL] Error: " + e);
    }
    """

    static let listClasses = """
    // List all loaded Objective-C classes
    // Optionally filter by a keyword

    var filter = "";  // Set to e.g. "Payment" to filter

    var classes = ObjC.enumerateLoadedClassesSync();
    var results = [];

    for (var image in classes) {
        classes[image].forEach(function(cls) {
            if (filter === "" || cls.indexOf(filter) !== -1) {
                results.push(cls);
            }
        });
    }

    results.sort();
    console.log("[*] Found " + results.length + " classes");
    results.forEach(function(cls) {
        console.log("  " + cls);
    });
    """

    static let interceptNetwork = """
    // Intercept HTTP/HTTPS requests
    // Logs URL, method, headers, and body

    var NSURLRequest = ObjC.classes.NSURLRequest;
    var NSMutableURLRequest = ObjC.classes.NSMutableURLRequest;

    Interceptor.attach(
        ObjC.classes.NSURLSession["- dataTaskWithRequest:completionHandler:"].implementation,
        {
            onEnter: function(args) {
                var request = ObjC.Object(args[2]);
                var url = request.URL().absoluteString().toString();
                var method = request.HTTPMethod().toString();

                console.log("\\n─── HTTP " + method + " ───");
                console.log("URL: " + url);

                var headers = request.allHTTPHeaderFields();
                if (headers) {
                    console.log("Headers: " + headers.toString());
                }

                var body = request.HTTPBody();
                if (body) {
                    var bodyStr = ObjC.classes.NSString
                        .alloc()
                        .initWithData_encoding_(body, 4); // NSUTF8
                    if (bodyStr) {
                        console.log("Body: " + bodyStr.toString());
                    }
                }
                console.log("────────────────────");
            }
        }
    );

    console.log("[NET] Intercepting HTTP requests...");
    """

    static let keychainDump = """
    // Dump Keychain items accessible to the current app

    var query = ObjC.classes.NSMutableDictionary.alloc().init();
    query.setObject_forKey_(ObjC.classes.kSecClassGenericPassword, ObjC.classes.kSecClass);
    query.setObject_forKey_(ObjC.classes.kSecMatchLimitAll, ObjC.classes.kSecMatchLimit);
    query.setObject_forKey_(true, ObjC.classes.kSecReturnAttributes);
    query.setObject_forKey_(true, ObjC.classes.kSecReturnData);

    var result = Memory.alloc(Process.pointerSize);
    var status = ObjC.classes.SecItemCopyMatching(query, result);

    if (status.valueOf() === 0) {
        var items = ObjC.Object(result.readPointer());
        var count = items.count().valueOf();
        console.log("[*] Found " + count + " keychain items\\n");

        for (var i = 0; i < count; i++) {
            var item = items.objectAtIndex_(i);
            var account = item.objectForKey_("acct");
            var service = item.objectForKey_("svce");
            var data = item.objectForKey_("v_Data");

            var value = "";
            if (data) {
                value = ObjC.classes.NSString
                    .alloc()
                    .initWithData_encoding_(data, 4)?.toString() ?? "<binary>";
            }

            console.log("─── Item " + (i + 1) + " ───");
            console.log("  Account: " + (account ? account.toString() : "N/A"));
            console.log("  Service: " + (service ? service.toString() : "N/A"));
            console.log("  Value:   " + value);
        }
    } else {
        console.log("[!] SecItemCopyMatching returned: " + status);
    }
    """
}
