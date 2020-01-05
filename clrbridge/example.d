#!/usr/bin/env rund
//!importPath dlib
//!importPath ../source
//!importPath ../source_cstring
//!importPath ../out/DerelictUtil/source

import std.file : thisExePath;
import std.path : buildPath, dirName;
import std.stdio;

import cstring;
import dflat;
import clrbridge;
import clrbridgeglobal;

static import dotnet;

int main()
{
    loadCoreclr();
    {
        CoreclrHostOptions options;
        auto propMap = coreclrDefaultProperties();
        const clrBridgePath = __FILE_FULL_PATH__.dirName;
        propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES] = pathcat(
            propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES],
            buildPath(clrBridgePath, "out", "ClrBridge.dll"));
        options.properties = CoreclrProperties(propMap);
        globalCoreclrHost.initialize(options);
    }
    scope (exit) globalCoreclrHost.shutdown();

    {
        const result = loadClrBridge(&globalCoreclrHost, &globalClrBridge);
        if (result.failed)
        {
            writefln("%s", result);
            return 1;
        }
    }

    // test failure
    {
        writefln("checking that error handling works...");
        Assembly assembly;
        const result = globalClrBridge.tryLoadAssembly(CStringLiteral!"WillFail", &assembly);
        writefln("got expected error: %s", result);
    }
    //loadAssembly("System, Version=2.0.3600.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");

    //globalClrBridge.funcs.TestArray([mscorlib.ptr, console.ptr, null].ptr);
    //globalClrBridge.funcs.TestVarargs(42);

    {
        const arr = globalClrBridge.arrayBuilderNewGeneric(globalClrBridge.primitiveTypes.Object, 10);
        scope(exit) globalClrBridge.release(arr);

        globalClrBridge.arrayBuilderAddGeneric(arr, globalClrBridge.primitiveTypes.Object);
        //globalClrBridge.arrayAdd(arr, 100);
    }

    const stringBuilderType = globalClrBridge.getType(globalClrBridge.mscorlib, CStringLiteral!"System.Text.StringBuilder");
    {
        enum size = 10;
        const arr = globalClrBridge.arrayBuilderNewGeneric(stringBuilderType, size);
        scope(exit) globalClrBridge.release(arr);

        static foreach (i; 0 .. size)
        {{
            const sb = globalClrBridge.newObject(stringBuilderType);
            scope(exit) globalClrBridge.release(sb);
            globalClrBridge.arrayBuilderAddGeneric(arr, sb);
        }}
    }

    // test value type array
    {
        enum size = 10;
        const arrayBuilder = globalClrBridge.arrayBuilderNewUInt32(size);
        scope(exit) globalClrBridge.release(arrayBuilder);
        foreach (i; 0 .. size)
        {
            globalClrBridge.arrayBuilderAddUInt32(arrayBuilder, i);
        }
        const array = globalClrBridge.arrayBuilderFinishUInt32(arrayBuilder);
        scope(exit) globalClrBridge.release(array);
        globalClrBridge.debugWriteObject(array);
    }

    const consoleType = globalClrBridge.getType(globalClrBridge.mscorlib, CStringLiteral!"System.Console");

    // demonstrate how to create an array manually
    {
        const builder = globalClrBridge.arrayBuilderNewGeneric(globalClrBridge.typeType, 1);
        scope (exit) globalClrBridge.release(builder);
        globalClrBridge.arrayBuilderAddGeneric(builder, globalClrBridge.primitiveTypes.String);
        const manualStringTypeArray = globalClrBridge.arrayBuilderFinishGeneric(builder);
        globalClrBridge.release(manualStringTypeArray);
    }
    const stringTypeArray = globalClrBridge.makeGenericArray(globalClrBridge.typeType, globalClrBridge.primitiveTypes.String);

    // test ambiguous method error
    {
        MethodInfo methodInfo;
        const result = globalClrBridge.tryGetMethod(consoleType, CStringLiteral!"WriteLine", ArrayGeneric.nullObject, &methodInfo);
        assert(result.type == ClrBridgeError.Type.forward);
        assert(result.data.forward.code == ClrBridgeErrorCode.ambiguousMethod);
        writefln("got expected error: %s",  result);
    }
    const consoleWriteLine = globalClrBridge.getMethod(consoleType, CStringLiteral!"WriteLine", stringTypeArray);
    globalClrBridge.funcs.CallStaticString(consoleWriteLine, CStringLiteral!"calling Console.WriteLine from D!");

    // call using object array
    {
        const msg = globalClrBridge.box!(dotnet.PrimitiveType.String)(CStringLiteral!"calling Console.WriteLine from D with Object Array!");
        scope(exit) globalClrBridge.release(msg);
        const args = globalClrBridge.makeObjectArray(msg);
        scope(exit) globalClrBridge.release(args);
        globalClrBridge.funcs.CallGeneric(consoleWriteLine, dotnet.DotNetObject.nullObject, args);
    }

    writeln("success");
    return 0;
}
