import clrtestsetup;
import simple;

void main()
{
    import std.stdio;

    clrSetup("Simple");
    scope (exit) clrCleanup();

    writeln("Calling NoOp...");
    Funcs.NoOp();
    //assert(42 == Funcs.FortyTwo());
    Funcs.FortyTwo();
    //assert(25 == Funcs.Square(5));
    //Funcs.Square(5);
    writefln("testSimple finished");
}
