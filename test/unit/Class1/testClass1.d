import dflat;

import class1;

void clrhostInit()
{
    import std.file : thisExePath;
    import std.path : buildPath, dirName;

    CLRCore.load();

    CoreclrOptions options;
    auto propMap = coreclrDefaultProperties();
    const exePath = thisExePath().dirName;
    propMap[TRUSTED_PLATFORM_ASSEMBLIES] = pathcat(propMap[TRUSTED_PLATFORM_ASSEMBLIES],
        buildPath(exePath, "Class1static.dll"),
        buildPath(exePath, "Class1.dll"));
    options.properties = CoreclrProperties(propMap);
    coreclrInit(&clrhost, options);
}

void main()
{
    clrhostInit();
    scope (exit) clrhost.shutdown();

    {
        import std.stdio;
        import std.string : fromStringz;
        writeln("here");
        Class1 a;
        writeln("`a` raw pointer: ", a._raw.o.p);
        a = Class1.make(314);
        writeln("`a` raw pointer: ", a._raw.o.p);
        writeln(a.toString().fromStringz);
        a.foo();
        writeln(a.toString().fromStringz);
        writeln(a.bar);
        a.bar = 42;
        writeln(a.bar);
        scope(exit) a.unpin();
    }

}

