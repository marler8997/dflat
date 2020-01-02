module buildlib;

import std.algorithm, std.datetime, std.exception, std.file, std.process, std.range, std.stdio, std.string;

class AlreadyReportedException : Exception { this() { super("error already reported"); } }

auto tryExec(scope const(char[])[] args)
{
    writefln("[EXEC] %s", escapeShellCommand(args));
    const result = execute(args);
    writeln(result.output.stripRight);
    if (result.status != 0)
        writefln("Error: last command failed with exit code %s", result.status);
    return result;
}

auto exec(scope const(char[])[] args)
{
    const result = tryExec(args);
    if (result.status != 0)
        throw new AlreadyReportedException();
    return result.output;
}

// We use a struct so we can define struct methods like toString and so
// we can do things like this:
// ---
// immutable(BuildRule)* foo = null;
// ...
// foo = bar;
// ...
// ---
struct BuildRule
{
    string name; /// optional string that can be used to identify this rule
    string target;
    string[] targets; // target files
    string[] sources; // source files
    immutable(BuildRule*)[] deps; // dependencies to build before this one
    bool delegate() condition; // Optional condition to determine whether or not to run this rule, checked after building dependencies
    void delegate() func;
    string description; /// optional string to describe this rule rather than printing the target files

    /// Finish creating the rule by checking that it is configured properly
    void finalize()
    {
        if (target)
        {
            assert(!targets, "target and targets cannot both be set");
            targets = [target];
        }
    }

    bool opEquals(ref const BuildRule other) const
    {
        return &this is &other;
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        if (name)
            sink(name);
        else if (target)
            sink(target);
        else
            sink("???");
    }
}

/// An input range for a recursive set of rules
struct BuildRuleRange
{
    private immutable(BuildRule*)[] next;
    private bool[immutable(BuildRule)*] added;
    this(immutable BuildRule*[] rules) { addRules(rules); }
    bool empty() const { return next.length == 0; }
    auto front() inout { return next[0]; }
    void popFront()
    {
        auto save = next[0];
        next = next[1 .. $];
        addRules(save.deps);
    }
    void addRules(immutable BuildRule*[] rules)
    {
        foreach (rule; rules)
        {
            if (!added.get(rule, false))
            {
                next ~= rule;
                added[rule] = true;
            }
        }
    }
}

immutable(BuildRule)* findRule(immutable BuildRule*[] roots, string matchString)
{
    immutable(BuildRule)* targetMatchRule = null;
    string targetMatchFile = null;

    // check if 'matchString' matches any rule names first
  LruleLoop:
    foreach (rule; BuildRuleRange(roots))
    {
        if (rule.name == matchString)
            return rule;
        foreach (target; rule.targets)
        {
            if (target.endsWith(matchString))
            {
                if (targetMatchRule is null || target.length < targetMatchFile.length)
                {
                    targetMatchRule = rule;
                    targetMatchFile = target;
                    continue LruleLoop;
                }
            }
        }
    }
    return targetMatchRule;
}

template Ref(T)
{
    static if (is(T == class))
        alias Ref = T;
    else
        alias Ref = T*;
}

/** Initializes an object using a chain of method calls */
struct MethodInitializer(T)
{
    private Ref!T obj;
    auto ref opDispatch(string name)(typeof(__traits(getMember, T, name)) arg)
    {
        mixin("obj." ~ name ~ " = arg;");
        return this;
    }
}

/** Create an object using a chain of method calls for each field. */
auto methodInit(T, alias Func, Args...)(Args args)
{
    auto initializer = MethodInitializer!T(new T());
    Func(initializer, initializer.obj, args);
    initializer.obj.finalize();
    return initializer.obj;
}

immutable(BuildRule)* makeRule(alias Func)()
{
    return methodInit!(BuildRule, Func).assumeUnique;
}

immutable(T)* assumeUnique(T)(T* t)
{
    return cast(immutable(T)*)t;
}

enum RuleStateEnum
{
    initial,
    building,
    skipped,
    executed,
}
struct RuleState
{
    RuleStateEnum enumValue;
}

struct RuleBuilder
{
    // since we are not parallel (yet), a simple list will do
    RuleState*[immutable(BuildRule)*] map;

    bool force;
    string[] implicitDeps;
    this(bool force, string[] implicitDeps)
    {
        this.force = force;
        this.implicitDeps = implicitDeps;
    }

    RuleState *getState(immutable(BuildRule)* rule)
    {
        auto state = map.get(rule, null);
        if (state is null)
        {
            state = new RuleState(RuleStateEnum.initial);
            map[rule] = state;
        }
        return state;
    }

    RuleState* build(immutable(BuildRule)* rule)
    {
        auto state = getState(rule);
        final switch (state.enumValue)
        {
            case RuleStateEnum.initial:
                state.enumValue = RuleStateEnum.building;
                bool depExecuted = false;
                foreach (dep; rule.deps)
                {
                    auto depState = build(dep);
                    if (depState.enumValue == RuleStateEnum.executed)
                        depExecuted = true;
                    else assert(depState.enumValue == RuleStateEnum.skipped, "code bug");
                }
                if (!force)
                {
                    if (rule.condition !is null && !rule.condition())
                    {
                        //writefln("skipping build of %-(%s%) as its condition returned false", targets);
                        state.enumValue = RuleStateEnum.skipped;
                        break;
                    }
                    if (!depExecuted && rule.targets && rule.targets.isUpToDate(chain(rule.sources, implicitDeps)))
                    {
                        //if (this.sources !is null)
                        //    log("Skipping build of %-(%s%) as it's newer than %-(%s%)", targets, this.sources);
                        state.enumValue = RuleStateEnum.skipped;
                        break;
                    }
                }
                //writefln("%s: depExecuted=%s rule.targets=%s upToDate=%s", *rule, depExecuted, rule.targets,
                //    rule.targets.isUpToDate(chain(rule.sources, implicitDeps)));
                if (rule.func !is null)
                {
                    rule.func();
                }

                // verify targets are up-to-date
                if (!rule.targets.isUpToDate(chain(rule.sources, implicitDeps)))
                {
                    writefln("%s: targets are not up-to-date after executing rule!", *rule);
                    writeln("Targets:");
                    foreach (target; rule.targets)
                    {
                        const time = target.timeLastModified.ifThrown(SysTime.init);
                        if (time == SysTime.init)
                            writefln("    DOES NOT EXIST: %s", target);
                        else
                            writefln("    %s: %s", time, target);
                    }
                    if (rule.sources.length == 0)
                        writeln("Sources: none");
                    else
                    {
                        writeln("Sources:");
                        foreach (source; rule.sources)
                        {
                           writefln("    %s: %s", source.timeLastModified.ifThrown(SysTime.init), source);
                        }
                    }
                    throw new AlreadyReportedException();
                }

                state.enumValue = RuleStateEnum.executed;
                break;
            case RuleStateEnum.building: assert(0, "recursive build rule detected!");
            case RuleStateEnum.skipped:
            case RuleStateEnum.executed:
                break;
        }
        return state;
    }

    void buildMultiple(immutable BuildRule*[] rules)
    {
        foreach (rule; rules)
        {
            build(rule);
        }
    }
}

bool isUpToDate(R, S)(R targets, S sources)
{
    auto oldestTargetTime = SysTime.max;
    foreach (target; targets)
    {
        version (Windows)
        {
            // ignore directories on windows, there's no easy way to update their timestamps
            if (target.isDir.ifThrown(false))
                continue;
        }
        const time = target.timeLastModified.ifThrown(SysTime.init);
        if (time == SysTime.init)
        {
            //writefln("[DEBUG] target '%s' does not exist", target);
            return false;
        }
        oldestTargetTime = min(time, oldestTargetTime);
    }
    foreach (source; sources)
    {
        const sourceTime = source.timeLastModified.ifThrown(SysTime.init);
        if (sourceTime > oldestTargetTime)
        {
            //writefln("[DEBUG] source '%s' (%s) is newer than %s", source, sourceTime, oldestTargetTime);
            return false;
        }
    }
    //writefln("[DEBUG] all these targets are up-to-date: %s", targets);
    return true;
}

T emptyToNull(T)(T s)
{
    return s.length == 0 ? null : s;
}

auto which(string program)
{
    if (program.canFind("/", "\\"))
        return program;
    version(Windows)
    {
        const result = ["where", program].execute;
        if (result.status != 0)
            return null;
        return result.output.lineSplitter.front.stripRight.emptyToNull;
    }
    else
    {
        const result = execute(["which", program]);
        return result.status == 0 ? result.output.stripRight.emptyToNull : null;
    }
}

/** Wrapper around std.file.copy that also updates the target timestamp. */
void copyAndTouch(RF, RT)(RF from, RT to)
{
    std.file.copy(from, to);
    const now = Clock.currTime;
    to.setTimes(now, now);
}

void touch(T)(T filename)
{
    try
    {
        const now = Clock.currTime;
        filename.setTimes(now, now);
    }
    catch (FileException e)
    {
        version (Windows)
        {
            if (isDir(filename).ifThrown(false))
            {
                // ignore, since there doesn't seem to be an easy way to do this on windows
                return;
            }
        }
        throw e;
    }
}

T exeName(T)(T filename)
{
    version (Windows)
        filename ~= ".exe";
    return filename;
}

immutable(BuildRule)* directoryRule(string dir, immutable(BuildRule*)[] deps)
{
    return makeRule!( (builder, rule) => builder
        .target(dir)
        .deps(deps)
        .func(() {
            if (!exists(rule.target))
            {
                writefln("mkdir '%s'", rule.target);
                mkdir(rule.target);
            }
            touch(rule.target);
        })
    );
}

//
// Downloader
//
class DownloadException : Exception
{
    this(string msg) { super(msg); }
}
struct Downloader
{
    enum Type
    {
        none,
        powershell,
        wget,
    }
    Type type;
    union
    {
        PowershellDownloader powershell;
        WgetDownloader wget;
    }

    static Downloader none() { return Downloader(Type.none); }
    private this(Type type) { this.type = type; }
    @disable this();
    this(PowershellDownloader dl)
    {
        this.type = Type.powershell;
        this.powershell = dl;
    }
    this(WgetDownloader dl)
    {
        this.type = Type.wget;
        this.wget = dl;
    }
    void download(string url, string to)
    {
        writefln("[DEBUG] download '%s' to '%s'", url, to);
        final switch (type)
        {
            case Type.none: throw new DownloadException("failed to find a download program");
            case Type.powershell: return powershell.download(url, to);
            case Type.wget: return wget.download(url, to);
        }
    }
}
struct PowershellDownloader
{
    string exe;
    void download(string url, string to)
    {
        exec([exe, "-NonInteractive", "-Command",
            `$client = new-object System.Net.WebClient;`,
            `$client.DownloadFile("` ~ url ~ `", "` ~ to ~ `")`
        ]);
    }
}
struct WgetDownloader
{
    string exe;
    void download(string url, string to)
    {
        exec([exe, url, "--output-document", to]);
    }
}

Downloader findDownloader()
{
    version (Windows)
    {
        {
            const exe = which("powershell");
            if (exe !is null)
                return Downloader(PowershellDownloader(exe));
        }
    }
    {
        const exe = which("wget");
        if (exe !is null)
            return Downloader(WgetDownloader(exe));
    }
    return Downloader.none;
}

//
// Unzipper
//
class UnzipException : Exception
{
    this(string msg) { super(msg); }
}
struct Unzipper
{
    enum Type
    {
        none,
        unzipProgram,
        sevenZip,
        powershell,
    }
    Type type;
    union
    {
        UnzipProgramUnzipper unzipProgram;
        SevenZipUnzipper sevenZip;
        PowershellUnzipper powershell;
    }

    static Unzipper none() { return Unzipper(Type.none); }
    private this(Type type) { this.type = type; }
    @disable this();
    this(UnzipProgramUnzipper u)
    {
        this.type = Type.unzipProgram;
        this.unzipProgram = u;
    }
    this(SevenZipUnzipper u)
    {
        this.type = Type.sevenZip;
        this.sevenZip = u;
    }
    this(PowershellUnzipper u)
    {
        this.type = Type.powershell;
        this.powershell = u;
    }
    void unzip(string archive, string to)
    {
        writefln("[DEBUG] unzipping '%s' to '%s' (type=%s)", archive, to, type);
        final switch (type)
        {
            case Type.none: throw new UnzipException("failed to find an unzip program");
            case Type.unzipProgram: return unzipProgram.unzip(archive, to);
            case Type.sevenZip: return sevenZip.unzip(archive, to);
            case Type.powershell: return powershell.unzip(archive, to);
        }
    }
}
struct UnzipProgramUnzipper
{
    string exe;
    void unzip(string archive, string to)
    {
        exec([exe, archive, "-d", to]);
    }
}
struct SevenZipUnzipper
{
    string exe;
    void unzip(string archive, string to)
    {
        exec([exe, "x", archive, "-o" ~ to, "-y", "-r"]);
    }
}
struct PowershellUnzipper
{
    string exe;
    void unzip(string archive, string to)
    {
        exec([exe, "-NonInteractive", "-Command",
            `Add-Type -AssemblyName System.IO.Compression.FileSystem;`,
            `[System.IO.Compression.ZipFile]::ExtractToDirectory("` ~ archive ~ `", "` ~ to ~ `")`
        ]);
        /*
        exec([exe, "-NonInteractive", "-Command",
            `Expand-Archive -LiteralPath ` ~ archive ~ ` -DestinationPath ` ~ to
        ]);
        */
    }
}
Unzipper findUnzipper()
{
    {
        const exe = which("unzip");
        if (exe !is null)
            return Unzipper(UnzipProgramUnzipper(exe));
    }
    {
        const exe = which("7z");
        if (exe !is null)
            return Unzipper(SevenZipUnzipper(exe));
    }
    version (Windows)
    {
        {
            const exe = which("powershell");
            if (exe !is null)
                return Unzipper(PowershellUnzipper(exe));
        }
    }
    return Unzipper.none;
}