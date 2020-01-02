import dflat;
import simple;

void clrhostInit()
{
    import std.file : thisExePath;
    import std.path : buildPath, dirName;

    CLRCore.load();

    CoreclrOptions options;
    auto propMap = coreclrDefaultProperties();
    const exePath = thisExePath().dirName;
    propMap[TRUSTED_PLATFORM_ASSEMBLIES] = pathcat(propMap[TRUSTED_PLATFORM_ASSEMBLIES],
        buildPath(exePath, "Simplestatic.dll"),
        buildPath(exePath, "Simple.dll"));
    options.properties = CoreclrProperties(propMap);
    coreclrInit(&clrhost, options);
}
void main()
{
    import std.stdio;

    clrhostInit();
    scope (exit) clrhost.shutdown();

    writeln("Calling NoOp...");
    Funcs.NoOp();
    //assert(42 == Funcs.FortyTwo());
    //assert(25 == Funcs.Square(5));
    writefln("testSimple finished");
}
