/**
Checkout API here: https://github.com/dotnet/coreclr/blob/master/src/coreclr/hosts/inc/coreclrhost.h
*/
module dflat.coreclr.lib;

import dflat.cstring;
import derelict.util.loader;

public
{
    import derelict.util.system;
    
    static if(Derelict_OS_Windows)
        enum defaultLibNames = `C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App\3.1.0\coreclr.dll`;
    else static if (Derelict_OS_Mac)
        enum defaultLibNames = "/usr/local/share/dotnet/shared/Microsoft.NETCore.App/2.2.3/libcoreclr.dylib";
    else static if (Derelict_OS_Linux)
        enum defaultLibNames = "libcoreclr.so";
    else
        static assert(0, "Need to implement CoreCLR libNames for this operating system.");
}

// TODO: this should come from a library like druntime
struct HRESULT
{
    private uint value;
    bool passed() const { return value == 0; }
    bool failed() const { return value != 0; }
    uint rawValue() const { return value; }
    void toString(Sink)(Sink sink) const
    {
        import std.format: formattedWrite;
        formattedWrite(sink, "0x%x", value);
    }
}

struct CoreclrFunc
{
    alias coreclr_initialize = extern(C) HRESULT function(
        CString exePath,
        CString appDomainFriendlyName,
        int propertyCount,
        const CString* propertyKeys,
        const CString* propertyValues,
        void** hostHandle,
        uint* domainId);

    alias coreclr_shutdown = extern(C) int function(void* hostHandle, uint domainId);

    alias coreclr_shutdown_2 = extern(C) int function(void* hostHandle, uint domainId, int* latchedExitCode);

    alias coreclr_create_delegate = extern(C) int function(
        void* hostHandle,
        uint domainId,
        CString entryPointAssemblyName,
        CString entryPointTypeName,
        CString entryPointMethodName,
        void** dg);

    alias coreclr_execute_assembly = extern(C) int function(
        void* hostHandle,
        uint domainId,
        int argc,
        const char** argv,
        const char* managedAssemblyPath,
        uint* exitCode);
}

private Exception notLoaded() { throw new Exception("the coreclr library has not been loaded, have you called dflat.coreclr.loadLibCoreclr?"); }
// TODO: see if there is a shorter way to define the notLoaded functions
private struct NotLoaded
{
    static extern(C) HRESULT coreclr_initialize(
        CString exePath,
        CString appDomainFriendlyName,
        int propertyCount,
        const CString* propertyKeys,
        const CString* propertyValues,
        void** hostHandle,
        uint* domainId)
    { throw notLoaded(); }

    static extern(C) int coreclr_shutdown(void* hostHandle, uint domainId)
    { throw notLoaded(); }

    static extern(C) int coreclr_shutdown_2(void* hostHandle, uint domainId, int* latchedExitCode)
    { throw notLoaded(); }

    static extern(C) int coreclr_create_delegate(
        void* hostHandle,
        uint domainId,
        CString entryPointAssemblyName,
        CString entryPointTypeName,
        CString entryPointMethodName,
        void** dg)
    { throw notLoaded(); }

    static extern(C) int coreclr_execute_assembly(
        void* hostHandle,
        uint domainId,
        int argc,
        const char** argv,
        const char* managedAssemblyPath,
        uint* exitCode)
    { throw notLoaded(); }
}

private __gshared string loadLibCoreclrLibName = null; // used by 'host.d' to find other libraries/assemblies
__gshared CoreclrFunc.coreclr_initialize       coreclr_initialize       = &NotLoaded.coreclr_initialize;
__gshared CoreclrFunc.coreclr_shutdown         coreclr_shutdown         = &NotLoaded.coreclr_shutdown;
__gshared CoreclrFunc.coreclr_shutdown_2       coreclr_shutdown_2       = &NotLoaded.coreclr_shutdown_2;
__gshared CoreclrFunc.coreclr_create_delegate  coreclr_create_delegate  = &NotLoaded.coreclr_create_delegate;
__gshared CoreclrFunc.coreclr_execute_assembly coreclr_execute_assembly = &NotLoaded.coreclr_execute_assembly;

/**
Load the coreclr library functions (i.e. coreclr_initialize, coreclr_shutdown, etc).
Params:
  libNames = A string containing one or more comma-separated shared library names.
*/
void loadLibCoreclr(string libNames = defaultLibNames)
{
    import core.atomic : atomicExchange;

    static shared calledAlready = false;
    if (atomicExchange(&calledAlready, true))
        throw new Exception("loadLibCoreclr was called more than once");

    static class CoreclrLoader : SharedLibLoader
    {
        this(string libNames) { super(libNames); }
        protected override void loadSymbols()
        {
            bindFunc(cast(void**)&coreclr_initialize, "coreclr_initialize");
            bindFunc(cast(void**)&coreclr_shutdown, "coreclr_shutdown");
            bindFunc(cast(void**)&coreclr_shutdown_2, "coreclr_shutdown_2");
            bindFunc(cast(void**)&coreclr_create_delegate, "coreclr_create_delegate");
            bindFunc(cast(void**)&coreclr_execute_assembly, "coreclr_execute_assembly");
        }
        public string libName() { return this.lib.name; }
    }
    auto loader = new CoreclrLoader(libNames);
    loader.load();
    loadLibCoreclrLibName = loader.libName;
    assert(loadLibCoreclrLibName !is null, "codebug: did not expect SharedLibLoader.lib.name to return null after calling load()");
}

string getCoreclrLibname()
in { if (loadLibCoreclrLibName is null) throw notLoaded(); } do
{
    return loadLibCoreclrLibName;
}
