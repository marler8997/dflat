import dflat;

static import helloworld;

void setupClrHost()
{
    CLRCore.load();

    import std.file, std.path;
    auto cwd = getcwd() ~ dirSeparator;
    string ep = thisExePath();

    auto tpas = pathcat(TrustedPlatformAssembliesFiles(),
                        buildPath([cwd, "test", "unit", "HelloWorld", "HelloWorldstatic.dll"]),
                        buildPath([cwd, "test", "unit", "HelloWorld", "HelloWorld.dll"]));
    //{import std.stdio; writeln(tpas);}
    clrhost = CLRHost(getcwd(),"foo",
        [
            TRUSTED_PLATFORM_ASSEMBLIES : tpas,
            APP_PATHS : getcwd(),
            APP_NI_PATHS : getcwd(),
            NATIVE_DLL_SEARCH_DIRECTORIES : getcwd(),
            SYSTEM_GC_SERVER : "false",
            SYSTEM_GLOBALISATION_INVARIANT : "false"
        ]);
}

void main()
{
    setupClrHost();
    scope (exit) clrhost.shutdown();

    helloworld.Funcs.SayHello();
}