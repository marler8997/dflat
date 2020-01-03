import clrtestsetup;
static import helloworld;

void main()
{
    clrSetup("HelloWorld");
    scope (exit) clrCleanup();

    helloworld.Funcs.SayHello();
}