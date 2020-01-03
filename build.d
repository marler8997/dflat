#!/usr/bin/env rund
import std.algorithm, std.array, std.conv, std.exception, std.file, std.getopt, std.path, std.range, std.stdio, std.string;

import buildlib;

int usage(T)(TargetsResult result, const string[BuildVar] vars, T getoptResult)
{
    defaultGetoptPrinter("./build.d <targets>..", getoptResult.options);
    writeln();
    // Print targets with a descriptions, name or single target
    writeln("Common Targets");
    writeln("------------");
    foreach (rule; BuildRuleRange(result.rootRules))
    {
        if (rule.description)
            writefln("%s | %s", *rule, rule.description);
        else if (rule.name)
            writefln("%s", rule.name);
        else if (rule.target)
            writefln("%s", rule.target);
    }
    writeln();
    writeln("Variables");
    writeln("------------");
    foreach (name; __traits(allMembers, BuildVar))
    {
        writefln("%s | default=%s", name, vars.get(__traits(getMember, BuildVar, name), "<none>"));
    }
    return 1;
}

int main(string[] args)
{
    try { return main2(args); }
    catch (AlreadyReportedException) { return 1; }
}
int main2(string[] args)
{
    // TODO: chdir to a random temporary directory so we know which works from any directory?
    auto getoptResult = getopt(args);

    string[BuildVar] vars;
    args = args[1..$];
    auto targetStrings = appender!(string[]);
    foreach (arg; args)
    {
        if (!tryParseVar(vars, arg))
            targetStrings.put(arg);
    }
    const makeTargetsResult = makeTargets(vars);
    if (getoptResult.helpWanted || targetStrings.data.length == 0)
        return usage(makeTargetsResult, vars, getoptResult);
    if (makeTargetsResult.errorCount > 0)
        return 1; // errors already printed
    const rootRules = makeTargetsResult.rootRules;

    auto rules = appender!(immutable(BuildRule*)[])();
    foreach (target; targetStrings.data)
    {
        auto rule = findRule(rootRules, target);
        if (rule is null)
        {
            writefln("Error: unknown target '%s'", target);
            return 1;
        }
        rules.put(rule);
    }

    enum thisBuildScript = __FILE_FULL_PATH__.buildNormalizedPath;
    auto builder = RuleBuilder(false, [thisBuildScript]);
    builder.buildMultiple(rules.data);

    writeln("Success");
    return 0;
}

auto repoPath(T...)(T args)
{
    return __FILE_FULL_PATH__.dirName.buildNormalizedPath(args);
}

string getOrSet(ref string[BuildVar] map, BuildVar name, lazy string default_)
{
    auto value = map.get(name, null);
    if (value is null)
    {
        value = default_;
        map[name] = value;
    }
    return value;
}

enum BuildVar
{
    dCompiler,
    dotnetCompiler,
    dotnetLoader,
    cecilDir,
}

bool tryParseVar(ref string[BuildVar] vars, string s)
{
    const equalIndex = s.indexOf('=');
    if (equalIndex == -1)
        return false;
    const varString = s[0 .. equalIndex];
    BuildVar varEnum;
    try { varEnum = to!BuildVar(varString); }
    catch (ConvException)
    {
        writefln("Error: build var '%s' does not exist", varString);
        throw new AlreadyReportedException();
    }
    vars[varEnum] = s[equalIndex + 1 .. $];
    return true;
}

struct TargetsResult
{
    uint errorCount;
    immutable(BuildRule*)[] rootRules;
}
auto makeTargets(ref string[BuildVar] vars)
{
    uint errorCount = 0;

    const outDir = directoryRule(repoPath("out"), null);

    const derelictUtil = makeRule!( (builder, rule) => builder
        .deps([outDir])
        .target(buildPath(outDir.target, "DerelictUtil"))
        // don't re-clone if we already have this directory, don't want to overwrite changes to it
        .condition(() => !exists(rule.target))
        .description("clone the DerelictUtil repo")
        .func(() {
            const derelictTmp = rule.target ~ ".cloning";
            if (exists(derelictTmp))
                rmdirRecurse(derelictTmp);
            mkdir(derelictTmp);
            exec(["git", "-C", derelictTmp, "init"]);
            exec(["git", "-C", derelictTmp, "remote", "add", "origin", "https://github.com/DerelictOrg/DerelictUtil"]);
            const release = "v3.0.0-beta.2";
            exec(["git", "-C", derelictTmp, "fetch", "origin", release]);
            exec(["git", "-C", derelictTmp, "reset", "--hard", "FETCH_HEAD"]);
            rename(derelictTmp, rule.target);
        })
    );

    const dotnetCompiler = vars.getOrSet(BuildVar.dotnetCompiler, () {
        auto compiler = which("csc");
        if (compiler is null)
        {
            errorCount++;
            writeln("Error: cannot find 'csc' in PATH, provide it with dotnetCompiler=...");
            compiler = "???";
        }
        return compiler;
    }());

    string cecilDir = vars.get(BuildVar.cecilDir, null);
    immutable(BuildRule*)[] csreflectDeps;
    if (cecilDir is null)
    {
        cecilDir = vars.getOrSet(BuildVar.cecilDir, buildPath(outDir.target, "Mono.Cecil"));
        csreflectDeps ~= makeRule!( (builder, rule) => builder
            .deps([outDir])
            .target(cecilDir)
            .condition(() => !exists(cecilDir))
            .func(() {
                const nupkg = cecilDir ~ ".nupkg";
                if (exists(nupkg))
                    remove(nupkg);
                auto downloader = findDownloader();
                downloader.download("https://www.nuget.org/api/v2/package/Mono.Cecil/0.11.1", nupkg);
                const extracting = cecilDir ~ ".extracting";
                if (exists(extracting))
                    rmdirRecurse(extracting);
                mkdir(extracting);
                auto unzipper = findUnzipper();
                unzipper.unzip(nupkg, extracting);
                remove(nupkg);
                rename(buildPath(extracting, "lib"), rule.target);
                rmdirRecurse(extracting);
            })
        );
    }
    const monoCecilDll = buildPath(cecilDir, "net40", "Mono.Cecil.dll");

    // Some options to find Mono.Cecil.dll at runtime
    //   1. Copy the dll to the output directory
    //   2. Create a runtime config to find it (different kinds for different versions of .NET)
    //   3. link the two binaries into 1
    //
    // For now I'm going to use 1 (copy binary) because it's simple and should work the same on all versions of .NET
    //
    const outCsreflectDir = directoryRule(buildPath(outDir.target, "csreflect"), [outDir]);
    const csreflectExe = buildPath(outCsreflectDir.target, "csreflect.exe");
    //const csreflectConfig = repoPath("csreflect", "app.config");
    const monoCecilDllRuntimeCopy = csreflectExe.dirName.buildPath(monoCecilDll.baseName);
    string[] csreflectRefs = [
        //"System",
        //"System.Core",
    ];
    auto monoSymbolWriter = "Mono.CompilerServices.SymbolWriter.dll";
    version (Windows)
        monoSymbolWriter = `C:\Program Files\Mono\lib\mono\4.5\` ~ monoSymbolWriter;
    const csreflectDllFileRefs = [
        monoSymbolWriter,
        monoCecilDll,
    ];
    auto csreflectCSharpSources = [repoPath("csreflect", "GenerateStaticMethodsCecil.cs")];
    const csreflect = makeRule!( (builder, rule) => builder
        .deps(chain(outCsreflectDir.only, csreflectDeps).array)
        .name("csreflect")
        .sources([monoCecilDll] ~ csreflectCSharpSources)
        .targets([csreflectExe, /*csreflectConfig,*/ monoCecilDllRuntimeCopy])
        .func(() {
            exec([
              dotnetCompiler,
              "/out:" ~ csreflectExe,
            ]
            //~ csreflectRefs.map!(e => "/reference:" ~ e ~ ".dll").array
            ~ csreflectDllFileRefs.map!(e => "/reference:" ~ e).array
            ~ csreflectCSharpSources);
            copyAndTouch(monoCecilDll, monoCecilDllRuntimeCopy);
        })
    );
    //
    // This is not needed to build csreflect but it can help development
    //

    const dotnetLoader = vars.getOrSet(BuildVar.dotnetLoader, () {
        version (Windows)
            return null;
        else
        {
            const dotnet = which("dotnet");
            if (dotnet !is null)
                return dotnet;
            const mono = which("mono");
            if (mono !is null)
                return mono;

            errorCount++;
            writefln("Error: neither 'dotnet' nor 'mono' are in PATH to run .NET programs, specify one with dotnetLoader=...");
            return "???";
        }
    }());
    //writefln("dotnetLoader = %s", dotnetLoader);

    string[] dotnetLoaderArgs;
    if (dotnetLoader)
        dotnetLoaderArgs = [dotnetLoader];

    const outTestDir = directoryRule(buildPath(outDir.target, "test"), [outDir]);
    const dCompiler = vars.getOrSet(BuildVar.dCompiler, which("dmd"));

    const unitTestParentDir = repoPath("test", "unit");
    auto testRules = dirEntries(unitTestParentDir, SpanMode.shallow).filter!(e => e.isDir).map!((unitTestDir) {
        const testName = unitTestDir.baseName;
        const thisTestDir = directoryRule(buildPath(outTestDir.target, testName), [outTestDir]);
        const dllRule = makeRule!( (builder, rule) => builder
            .deps([thisTestDir])
            .target(buildPath(thisTestDir.target, testName ~ ".dll"))
            .func(() {
                exec([dotnetCompiler, "/t:library",
                    "/out:" ~ rule.target,
                    buildPath(unitTestDir, testName ~ ".cs")]);
            })
        );
        const wrapperSource = makeRule!( (builder, rule) => builder
            .deps([dllRule, csreflect])
            .target(buildPath(thisTestDir.target, testName.toLower() ~ ".d"))
            .func(() {
                writefln("reflecting on '%s'", testName);
                exec(dotnetLoaderArgs ~ [
                    csreflect.targets[0],
                    testName,
                    thisTestDir.target.dirName,
                    thisTestDir.target
                ]);
            })
        );
        const compiledWrapper = makeRule!( (builder, rule) => builder
            .deps([wrapperSource, derelictUtil])
            .target(buildPath(thisTestDir.target, testName.exeName))
            .sources([wrapperSource.target,
                buildPath(unitTestDir, "test" ~ testName ~ ".d")])
            .func(() {
                string[] extraDCompilerArgs;
                version (Windows) {
                    extraDCompilerArgs = ["ole32.lib"];
                }
                exec([dCompiler,
                      "-g", "-debug",
                      "-I" ~ repoPath("source"),
                      "-I" ~ repoPath("test"),
                      "-I" ~ absolutePath(buildPath(derelictUtil.target, "source")),
                      "-i",
                      //"-o-",
                      "-of=" ~ rule.target
                     ] ~ extraDCompilerArgs ~ rule.sources);
            })
        );
        return makeRule!( (builder, rule) => builder
            .deps([compiledWrapper])
            .name("test" ~ testName)
            .target(buildPath(thisTestDir.target, testName ~ ".passed"))
            .func(() {
                exec([compiledWrapper.target]);
                std.file.write(rule.target, "");
                touch(rule.target);
            })
        );
    }).array.assumeUnique;

    const allTests = makeRule!( (builder, rule) => builder
        .name("alltests")
        .deps(testRules)
    );

    auto rootRules = appender!(immutable(BuildRule*)[])();
    rootRules.put(makeRule!( (builder, rule) => builder
        .name("dump-rules")
        .func(() {
            foreach (rule; BuildRuleRange(rootRules.data))
            {
                writeln("--------------------------------------------------------------------------------");
                writefln("%s", rule);
                writefln("rule.name: %s", rule.name);
                writefln("%s deps: %s", rule.deps.length, rule.deps);
                writefln("targets: %s", rule.targets);
            }
        })
    ));
    rootRules.put(allTests);
    rootRules.put(derelictUtil);
    rootRules.put(csreflectProjectsTarget(outCsreflectDir, csreflectRefs, csreflectDllFileRefs, csreflectCSharpSources));
    return TargetsResult(errorCount, rootRules.data);
}

auto csreflectProjectsTarget(immutable(BuildRule)* outCsreflectDir, const string[] refs, const string[] dllFileRefs, const string[] sources)
{
    import std.uuid : randomUUID;

    const solution2008 = buildPath(outCsreflectDir.target, "csreflect.2008.sln");
    const csproj2008 = buildPath(outCsreflectDir.target, "csreflect.2008.csproj");
    const csprojUser2008 = buildPath(outCsreflectDir.target, "csreflect.2008.csproj.user");
    const csproj2017 = buildPath(outCsreflectDir.target, "csreflect.2017.csproj");
    return makeRule!( (builder, rule) => builder
        .deps([outCsreflectDir])
        .name("csreflectProjects")
        .targets([solution2008, csproj2008, csprojUser2008, csproj2017])
        .func(() {
            import visualstudio;
            const csprojUuid = randomGuid();

            writeSolution2008(File(solution2008, "w"), csprojUuid);
            writeCsproj2008(File(csproj2008, "w"), "csreflect", csprojUuid, refs, dllFileRefs, sources);
            writeCsprojUser2008(File(csprojUser2008, "w"));

            writeCsproj2017(File(csproj2017, "w"), "csreflect", csprojUuid, refs, dllFileRefs, sources);
        })
    );
}
