// TODO: rename this to backend/coreclr.d
module dflat.coreclr.host;

import dflat.cstring;
import dflat.coreclr.lib;
import std.stdio;
private import std.path;
import std.file;
import std.algorithm;
import std.range;


string defaultTrustedPlatformAssembliesFiles(string dir = dirName(dflat.coreclr.lib.getCoreclrLibname))
{
    immutable extensions = [
        "*.ni.dll", // Probe for .ni.dll first so that it's preferred
        "*.dll",    // if ni and il coexist in the same dir
        "*.ni.exe", // ditto
        "*.exe",
    ];
    import std.array;
    Appender!string assemblies;
    bool[string] added;

    string prefix = "";
    foreach(extension; extensions)
    foreach(entry; dirEntries(dir, extension, SpanMode.shallow).filter!(e => e.isFile))
    {
        if (entry.name !in added)
        {
            added[entry.name] = true;
            assemblies.put(prefix);
            assemblies.put(entry.name);
            prefix = pathSeparator;
        }
    }

    return assemblies.data;
}

struct CLRHost
{
    private void* handle;
    private uint domainId; // an isolation unit within a process

    void shutdown()
    {
        coreclr_shutdown(handle, domainId);
    }

    int shutdown_2()
    {
        int ret;
        coreclr_shutdown_2(handle, domainId, &ret);
        return ret;
    }

    /**
     * entryPointAssemblyName (CLR dynamic library or exectuable)
     * entryPointTypeName class name
     */
    void* create_delegate(string entryPointAssemblyName,
                          string entryPointTypeName,
                          string entryPointMethodName)
    {
        void* dg;

        // TODO: use tempCString instead???
        auto err = coreclr_create_delegate(handle, domainId,
                                entryPointAssemblyName.toCString,
                                entryPointTypeName.toCString,
                                entryPointMethodName.toCString,
                                &dg);
        if (err)
        {
            import std.stdio;
            writeln("create_delegate error! err =",err);
            writeln(entryPointAssemblyName);
            writeln(entryPointTypeName);
            writeln(entryPointMethodName);
        }
        return dg;
    }
}

__gshared CLRHost clrhost;

struct CoreclrProperties
{
    private uint count;
    const(CString)* keys;
    const(CString)* values;

    this(string[string] propMap)
    in { assert(propMap.length <= uint.max); } do
    {
        import std.array;
        import std.string;
        import std.algorithm : each, map;
        this.count = cast(uint)propMap.length;
        this.keys = propMap.keys.map!(e => CString(e.toStringz)).array.ptr;
        this.values = propMap.values.map!(e => CString(e.toStringz)).array.ptr;
    }
}

enum StandardCoreclrProp : string
{
    /// pathSeparator separated list of directories
    APP_PATHS = "APP_PATHS",
    /// pathSeparator separated list of files. See TrustedPlatformAssembliesFiles
    TRUSTED_PLATFORM_ASSEMBLIES = "TRUSTED_PLATFORM_ASSEMBLIES",
    /// pathSeparator separated list of directories
    APP_NI_PATHS = "APP_NI_PATHS",
    /// pathSeparator separated list of directories
    NATIVE_DLL_SEARCH_DIRECTORIES = "NATIVE_DLL_SEARCH_DIRECTORIES",
    /// boolean
    SYSTEM_GC_SERVER = "System.GC.Server",
    /// boolean
    SYSTEM_GLOBALISATION_INVARIANT = "System.Globalization.Invariant",
}

string[string] coreclrDefaultProperties()
{
    const cwd = getcwd();
    return [
        StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES : defaultTrustedPlatformAssembliesFiles(),
        StandardCoreclrProp.APP_PATHS : cwd,
        StandardCoreclrProp.APP_NI_PATHS : cwd,
        StandardCoreclrProp.NATIVE_DLL_SEARCH_DIRECTORIES : cwd,
        StandardCoreclrProp.SYSTEM_GC_SERVER : "false",
        StandardCoreclrProp.SYSTEM_GLOBALISATION_INVARIANT : "false"
    ];
}

struct CoreclrOptions
{
    CString exePath;
    CString appDomainFriendlyName;
    CoreclrProperties properties;
}

HRESULT tryCoreclrInit(CLRHost* host, const ref CoreclrOptions options)
{
    import std.internal.cstring : tempCString;

    // TODO: verify we can use tempCString
    if (options.exePath is null)
    {
        const exePath = tempCString(thisExePath);
        const newOptions = const CoreclrOptions(CString(exePath), options.appDomainFriendlyName, options.properties);
        return tryCoreclrInit(host, newOptions);
    }

    const appDomain = options.appDomainFriendlyName ? options.appDomainFriendlyName : options.exePath;

    version (DebugCoreclr)
    {
        writefln("calling coreclr_initialize...");
        writefln("exePath = '%s'", options.exePath);
        writefln("appDomainFriendlyName = '%s'", options.appDomainFriendlyName);
        writefln("%s properties:", options.properties.count);
        foreach (i; 0 .. options.properties.count)
        {
            writefln("%s=%s", options.properties.keys[i], options.properties.values[i]);
        }
    }
    const result = coreclr_initialize(
        options.exePath, // absolute path of the native host executable
        appDomain,
        options.properties.count,
        options.properties.keys,
        options.properties.values,
        &host.handle, &host.domainId);
    version (DebugCoreclr)
    {
        writefln("coreclr_initialize returned %s", result);
    }
    return result;
}

void coreclrInit(CLRHost* host, const ref CoreclrOptions options)
{
    const result = tryCoreclrInit(host, options);
    if (result.failed)
    {
        import std.format : format;
        throw new Exception(format("coreclr_initialize failed, result=0x%08x", result.rawValue));
    }
}
