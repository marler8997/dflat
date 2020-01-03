import clrtestsetup;
import class1;

void main()
{
    clrSetup("Class1");
    scope (exit) clrCleanup();

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

