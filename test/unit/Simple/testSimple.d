import dflat;
import simple;

void setupClrHost()
{
    CLRCore.load();

    import std.file, std.path;
    auto cwd = getcwd() ~ dirSeparator;
    string ep = thisExePath();

    auto tpas = pathcat(TrustedPlatformAssembliesFiles(),
                        buildPath([cwd, "test", "unit", "Simple", "Simplestatic.dll"]),
                        buildPath([cwd, "test", "unit", "Simple", "Simple.dll"]));
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
    import std.stdio;

    setupClrHost();
    scope (exit) clrhost.shutdown();

    writeln("Calling NoOp...");
    Funcs.NoOp();
    //assert(42 == Funcs.FortyTwo());
    //assert(25 == Funcs.Square(5));
    writefln("testSimple finished");
}
