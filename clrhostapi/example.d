#!/usr/bin/env rund
//!importPath ../../mar/src
//!library C:\Program Files (x86)\Windows Kits\NETFXSDK\4.6.1\Lib\um\x86\mscoree.lib
//TODO: must be compiled with -m32mscoff because the mscoree.lib file is mscoff

// taking example from:
// https://blogs.msdn.microsoft.com/calvin_hsia/2013/12/05/use-reflection-from-native-c-code-to-run-managed-code/
import std.stdio;

import mar.sentinel : lit;
import mar.c : cint;
import mar.windows : HResult;
import mar.windows.kernel32 : GetCurrentProcess;
import mar.windows.ole32.nolink : IUnknown, IEnumUnknown;
import mar.windows.mscoree;

void enforceGoodHresult(HResult result, lazy string context)
{
    import core.stdc.stdlib : exit;

    if (result.failed)
    {
        writefln("Error: %s failed with hresult %s", context, result);
        exit(1);
    }
}

int main(string[] args)
{
    writefln("CLSID_CLRMetaHost: %s", ICLRMetaHost.id);

    ICLRMetaHost* clrMetaHost;
    CLRCreateInstanceOf(&CLRMetaHost.id, &clrMetaHost)
         .enforceGoodHresult("CLRCreateInstance");

    printRuntimes(clrMetaHost);

    ICLRRuntimeInfo* runtimeInfo;
    clrMetaHost.getRuntimeOf(lit!"v4.0.30319"w.ptr.asConst, &runtimeInfo)
        .enforceGoodHresult("getRuntimeInfo");

    ICorRuntimeHost *runtimeHost;
    runtimeInfo.getInterfaceOf(&CorRuntimeHost.id, &runtimeHost)
        .enforceGoodHresult("getRuntimeHost");

    writeln("[DEBUG] got runtime host, starting...");
    runtimeHost.start().enforceGoodHresult("start runtime host");

    writeln("[DEBUG] stopping runtime host...");
    runtimeHost.stop().enforceGoodHresult("stop runtime host");

    writeln("success");
    return 0;
}

// Just an example function for looping through the runtimes
void printRuntimes(ICLRMetaHost* clrMetaHost)
{
    IEnumUnknown* enumerator;
    clrMetaHost.enumerateInstalledRuntimes(&enumerator)
        .enforceGoodHresult("enumerateInstalledRuntimes");
    scope (exit) enumerator.release();

    for (;;)
    {
        ICLRRuntimeInfo* runtimeInfo;
        const result = enumerator.next(1, cast(IUnknown**)&runtimeInfo, null);
        if (result.isFalse)
            break;
        result.enforceGoodHresult("IEnumUnknown.next");
        scope (exit) runtimeInfo.release();
        
        {
            wchar[300] buffer = void;
            uint versionStringLength = buffer.length;
            runtimeInfo.getVersionString(buffer.ptr, &versionStringLength)
                .enforceGoodHresult("getVersionString");
            if (versionStringLength > 0)
                versionStringLength--;
            const versionString = buffer[0 .. versionStringLength];
            writefln("runtime version '%s'", versionString);
        }
        {
            wchar[300] buffer = void;
            uint runtimeDirLength = buffer.length;
            runtimeInfo.getRuntimeDirectory(buffer.ptr, &runtimeDirLength)
                .enforceGoodHresult("getRuntimeDirectory");
            if (runtimeDirLength > 0)
                runtimeDirLength--;
            const runtimeDir = buffer[0 .. runtimeDirLength];
            writefln("    dir '%s'", runtimeDir);
        }
        cint loaded;
        runtimeInfo.isLoaded(GetCurrentProcess(), &loaded).enforce("ICLRRuntimeInfo.isLoaded");
        writefln("    loaded in current process: %s", loaded);

    }
}