module clrtestsetup;

import dflat;

void clrSetup(string name)
{
    import std.file : thisExePath;
    import std.path : buildPath, dirName;

    loadCoreclr();
    CoreclrHostOptions options;
    auto propMap = coreclrDefaultProperties();
    const exePath = thisExePath().dirName;
    propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES] =pathcat(
        propMap[StandardCoreclrProp.TRUSTED_PLATFORM_ASSEMBLIES],
        buildPath(exePath, name ~ "static.dll"),
        buildPath(exePath, name ~ ".dll"));
    options.properties = CoreclrProperties(propMap);
    globalCoreclrHost.initialize(options);
}
void clrCleanup()
{
    globalCoreclrHost.shutdown();
}
