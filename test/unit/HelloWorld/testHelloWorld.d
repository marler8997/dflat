import dflat;

static import helloworld;

void clrhostInit()
{
    import std.file : thisExePath;
    import std.path : buildPath, dirName;

    loadLibCoreclr();
    CoreclrOptions options;
    auto propMap = coreclrDefaultProperties();
    const exePath = thisExePath().dirName;
    propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES] =pathcat(
        propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES],
        buildPath(exePath, "HelloWorldstatic.dll"),
        buildPath(exePath, "HelloWorld.dll"));
    options.properties = CoreclrProperties(propMap);
    coreclrInit(&clrhost, options);
}

void main()
{
    clrhostInit();
    scope (exit) clrhost.shutdown();

    helloworld.Funcs.SayHello();
}