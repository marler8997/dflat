import clrtestsetup;
static import namespaces;

void main()
{
    clrSetup("Namespaces");
    scope (exit) clrCleanup();

    namespaces.Bar.Baz();
}