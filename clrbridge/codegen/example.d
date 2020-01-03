#!/usr/bin/env rund
//!importPath out
//!importPath ../dlib
//!importPath ../../source
//!importPath ../../source_cstring
//!importPath ../../out/DerelictUtil/source

import std.file : thisExePath, exists;
import std.path : buildPath, dirName;
import std.stdio;

import cstring;
import clrbridge;

import mscorlib.System;

int main(string[] args)
{
    initGlobalClrBridge(buildPath(__FILE_FULL_PATH__.dirName.dirName.dirName, "out", "ClrBridge.dll"));

    foreach (i; 0 .. 4)
        Console.WriteLine();
    Console.WriteLine(false);
    Console.WriteLine(true);
    Console.WriteLine(CStringLiteral!"hello!");
    foreach (i; 0 .. 4)
        Console.WriteLine();

    return 0;
}
