module pkg_config;

auto pkgConfig(in string lib, in string minVersion=null)
{
    PkgConfig pc;
    pc._lib = lib;
    pc._minVersion = minVersion;
    return pc;
}

version (DubPR1453) {

    bool pkgConfigDubLines(in string lib, in string minVersion=null)
    {
        try {
            auto pc = pkgConfig(lib, minVersion)
                .libs()
                .msvc();
            auto library = pc.invoke();
            library.echoDubLines();
            return true;
        }
        catch (Exception ex) {
            import std.stdio : stderr;
            stderr.writeln(ex.msg);
            return false;
        }
    }

    version(linux) unittest {
        import std.exception : assertNotThrown;
        assert(pkgConfigDubLines("libpng", "1.6.0"));
        assert(!pkgConfigDubLines("libpng", "99.0"));
    }

}


class LibraryNotFound : Exception {
    this (string msg) {
        super(msg);
    }
}

struct Library
{
    import std.stdio : File, stdout;

    string name;
    string ver;
    string[] includePaths;
    string[] defines;
    string[] otherCFlags;
    string[] libPaths;
    string[] libs;
    string[] otherLFlags;

    version (DubPR1453) void echoDubLines(File f=stdout)
    {
        import std.algorithm : map;
        import std.array : join;
        import std.format : format;

        if (libs.length)
            f.writeln(
                "dub:sdl:libs ",
                libs.map!(l => format("\"%s\"", l)).join(" ")
            );
        if (libPaths.length)
            f.writeln(
                "dub:sdl:lflags ",
                libPaths.map!(p => format("\"%s\"", p)).join(" ")
            );
        if (otherLFlags)
            f.writeln(
                "dub:sdl:lflags ",
                otherLFlags.map!(f => format("\"%s\"", f)).join(" ")
            );
    }

    private void parseCFlags(string flagStr)
    {
        import std.algorithm : startsWith;

        const flags = splitFlags(flagStr);

        foreach (f; flags) {
            if (f.startsWith("-I")) {
                includePaths ~= f[2 .. $];
            }
            else if (f.startsWith("-D")) {
                defines ~= f[2 .. $];
            }
            else {
                otherCFlags ~= f;
            }
        }
    }

    private void parseLFlags(string flagStr)
    {
        import std.algorithm : startsWith;

        const flags = splitFlags(flagStr);

        foreach (f; flags) {
            if (f.startsWith("-L")) {
                libPaths ~= f[2 .. $];
            }
            else if (f.startsWith("-l")) {
                libs ~= f[2 .. $];
            }
            else {
                otherLFlags ~= f;
            }
        }
    }
}

struct PkgConfig
{
    private string _lib;
    private string _minVersion;
    private string _exe = defaultExe;
    private string[] _pkgConfigPath;
    private bool _cflags;
    private bool _libs;
    private bool _systemLibs;
    private bool _static;
    version(Windows) private bool _msvc;

    PkgConfig exe(in string exe) {
        _exe = exe;
        return this;
    }
    PkgConfig pkgConfigPath(in string path) {
        _pkgConfigPath = [ path ];
        return this;
    }
    PkgConfig pkgConfigPath(in string[] paths) {
        _pkgConfigPath = paths.dup;
        return this;
    }
    PkgConfig cflags() {
        _cflags = true;
        return this;
    }
    PkgConfig libs() {
        _libs = true;
        return this;
    }
    PkgConfig systemLibs() {
        _systemLibs = true;
        return this;
    }
    PkgConfig staticLib() {
        _static = true;
        return this;
    }
    PkgConfig msvc() {
        version(Windows) {
            _msvc = true;
        }
        return this;
    }

    Library invoke()
    {
        auto env = buildCmdEnv();

        // checking for package support
        run!LibraryNotFound(["--exists"], env);

        Library lib;
        lib.name = _lib;
        lib.ver = run!Exception(["--modversion"], env);
        if (_cflags) {
            lib.parseCFlags(run!Exception(["--cflags"], env));
        }
        if (_libs) {
            lib.parseLFlags(run!Exception(["--libs"], env));
        }
        return lib;
    }

    private string[string] buildCmdEnv()
    {
        string[string] env;
        if (_pkgConfigPath) {
            import std.array : join;
            import std.process : environment;
            string path = _pkgConfigPath.join(pathEnvSep);
            const curVal = environment.get("PKG_CONFIG_PATH", null);
            if (curVal) {
                path ~= pathEnvSep ~ curVal;
            }
            env["PKG_CONFIG_PATH"] = path;
        }
        if (_systemLibs) {
            env["PKG_CONFIG_ALLOW_SYSTEM_LIBS"] = "1";
        }
        return env;
    }

    private string run (Ex = Exception)(string[] args, string[string] env)
    {
        import std.array : join;
        import std.process : Config, pipe, spawnProcess, wait;
        import std.stdio : stdin, stderr;
        import std.string : strip;

        auto p = pipe();
        auto cmdArgs = [ _exe, "--print-errors", "--errors-to-stdout"];
        if (_static) {
            cmdArgs ~= "--static";
        }
        version(Windows) if (_msvc) {
            cmdArgs ~= "--msvc-syntax";
        }
        cmdArgs ~= args;
        if (_minVersion) {
            cmdArgs ~= (_lib ~ " >= " ~ _minVersion);
        }
        else {
            cmdArgs ~= _lib;
        }
        auto pid = spawnProcess(cmdArgs, stdin, p.writeEnd, stderr, env);
        string output = p.readEnd.byLine().join("\n").strip().idup;
        if (wait(pid)) {
            throw new Ex(output);
        }
        return output;
    }
}

private:

string[] splitFlags(string flagStr) pure
{
    import std.uni : isSpace;
    string[] flags;
    string flag;
    bool escaped;
    foreach(c; flagStr) {
        if (escaped) {
            escaped = false;
            flag ~= c;
        }
        else {
            if (c == '\\') {
                escaped = true;
            }
            else if (isSpace(c)) {
                if (flag.length) {
                    flags ~= flag;
                    flag.length = 0;
                }
            }
            else {
                flag ~= c;
            }
        }
    }
    if (flag.length) flags ~= flag;
    return flags;
}

version(Windows) {
    enum exeExt = ".exe";
    enum pathEnvSep = ";";
}
else {
    enum exeExt = "";
    enum pathEnvSep = ":";
}

enum defaultExe = "pkg-config" ~ exeExt;
