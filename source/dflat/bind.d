/**
Checkout API here: https://github.com/dotnet/coreclr/blob/master/src/coreclr/hosts/inc/coreclrhost.h
*/
module dflat.bind;

import dflat.cstring;
import derelict.util.loader;

public
{
    import derelict.util.system;
    
    static if(Derelict_OS_Windows)
        enum libNames = `C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App\3.1.0\coreclr.dll`;
    else static if (Derelict_OS_Mac)
        enum libNames = "/usr/local/share/dotnet/shared/Microsoft.NETCore.App/2.2.3/libcoreclr.dylib";
    else static if (Derelict_OS_Linux)
        enum libNames = "libcoreclr.so";
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

alias da_coreclr_initialize = extern(C) HRESULT function(CString exePath, CString appDomainFriendlyName, int propertyCount, const CString* propertyKeys, const CString* propertyValues, void** hostHandle, uint* domainId);
alias da_coreclr_shutdown = extern(C) int function(void* hostHandle, uint domainId);
alias da_coreclr_shutdown_2 = extern(C) int function(void* hostHandle, uint domainId, int* latchedExitCode);
alias da_coreclr_create_delegate = extern(C) int function(void* hostHandle, uint domainId, CString entryPointAssemblyName, CString entryPointTypeName, CString entryPointMethodName, void** dg);
alias da_coreclr_execute_assembly = extern(C) int function(void* hostHandle, uint domainId, int argc, const char** argv, const char* managedAssemblyPath, uint* exitCode);

__gshared
{
    da_coreclr_initialize coreclr_initialize;
    da_coreclr_shutdown coreclr_shutdown;
    da_coreclr_shutdown_2 coreclr_shutdown_2;
    da_coreclr_create_delegate coreclr_create_delegate;
    da_coreclr_execute_assembly coreclr_execute_assembly;
}
class CLRCoreLoader : SharedLibLoader
{
    protected
    {
        override void loadSymbols()
        {
            bindFunc(cast(void**)&coreclr_initialize, "coreclr_initialize");
            bindFunc(cast(void**)&coreclr_shutdown, "coreclr_shutdown");
            bindFunc(cast(void**)&coreclr_shutdown_2, "coreclr_shutdown_2");
            bindFunc(cast(void**)&coreclr_create_delegate, "coreclr_create_delegate");
            bindFunc(cast(void**)&coreclr_execute_assembly, "coreclr_execute_assembly");
        }
    }

    public
    {
        this()
        {
            super(libNames);
        }
    }
}

__gshared CLRCoreLoader CLRCore;

shared static this()
{
    CLRCore = new CLRCoreLoader();
}
