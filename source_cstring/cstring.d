module cstring;

struct CString
{
    private const(char)* _ptr;
    const(char)* ptr() const { return cast(const(char)*)_ptr; }
    alias ptr this;
    void toString(Sink)(Sink sink) const
    {
        import core.stdc.string : strlen;
        if (_ptr is null)
            sink("<null>");
        else
            sink(_ptr[0 .. strlen(_ptr)]);
    }
}

enum CStringLiteral(string s) = CString(s.ptr);

immutable(CString) toCString(scope const(char)[] s) pure nothrow @trusted
{
    import std.string : toStringz;
    return immutable CString(toStringz(s));
}
immutable(CString) toCString(scope return string s) pure nothrow @trusted
{
    import std.string : toStringz;
    return immutable CString(toStringz(s));
}
