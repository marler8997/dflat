module visualstudio;

import std.algorithm : canFind;
import std.path : baseName, stripExtension;
import std.stdio : File;

string randomGuid()
{
    import std.uuid : randomUUID;
    import std.conv : to;
    import std.string : toUpper;

    return randomUUID().to!string.toUpper();
}

void writeSolution2008(File file, string csprojUUID)
{
    const uuid = randomGuid();
    file.writefln(`Microsoft Visual Studio Solution File, Format Version 10.00`);
    file.writefln(`# Visual Studio 2008`);
    file.writefln(`Project("{%s}") = "csreflect.2008", "csreflect.2008.csproj", "{%s}"`, uuid, csprojUUID);
    file.writefln(`EndProject`);
    file.writefln(`Global`);
    file.writefln(`    GlobalSection(SolutionConfigurationPlatforms) = preSolution`);
    file.writefln(`        Debug|Any CPU = Debug|Any CPU`);
    file.writefln(`        Release|Any CPU = Release|Any CPU`);
    file.writefln(`    EndGlobalSection`);
    file.writefln(`    GlobalSection(ProjectConfigurationPlatforms) = postSolution`);
    file.writefln(`        {%s}.Debug|Any CPU.ActiveCfg = Debug|Any CPU`, csprojUUID);
    file.writefln(`        {%s}.Debug|Any CPU.Build.0 = Debug|Any CPU`, csprojUUID);
    file.writefln(`        {%s}.Release|Any CPU.ActiveCfg = Release|Any CPU`, csprojUUID);
    file.writefln(`        {%s}.Release|Any CPU.Build.0 = Release|Any CPU`, csprojUUID);
    file.writefln(`    EndGlobalSection`);
    file.writefln(`    GlobalSection(SolutionProperties) = preSolution`);
    file.writefln(`        HideSolutionNode = FALSE`);
    file.writefln(`    EndGlobalSection`);
    file.writefln(`EndGlobal`);
}
void writeCsproj2008(File file, string exeName, string uuid, const string[] refs, const string[] dllFileRefs, const string[] sources)
{
    file.writefln(`<?xml version="1.0" encoding="utf-8"?>`);
    file.writefln(`<Project ToolsVersion="3.5" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">`);
    file.writefln(`  <PropertyGroup>`);
    file.writefln(`    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>`);
    file.writefln(`    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>`);
    file.writefln(`    <SchemaVersion>2.0</SchemaVersion>`);
    file.writefln(`    <ProjectGuid>{%s}</ProjectGuid>`, uuid);
    file.writefln(`    <OutputType>Library</OutputType>`);
    file.writefln(`    <AssemblyName>%s</AssemblyName>`, exeName);
    file.writefln(`    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>`);
    file.writefln(`    <TargetFrameworkVersion>v3.5</TargetFrameworkVersion>`);
    file.writefln(`    <FileAlignment>512</FileAlignment>`);
    file.writefln(`    <WarningLevel>4</WarningLevel>`);
    file.writefln(`    <ErrorReport>prompt</ErrorReport>`);
    file.writefln(`    <OutputPath Condition=" '$(Platform)' == 'AnyCPU' ">bin\$(Configuration)\</OutputPath>`);
    file.writefln(`    <OutputPath Condition=" '$(Platform)' != 'AnyCPU' ">bin\$(Platform)\$(Configuration)\</OutputPath>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <PropertyGroup Condition=" '$(Configuration)' == 'Debug'">`);
    file.writefln(`    <DebugSymbols>true</DebugSymbols>`);
    file.writefln(`    <DebugType>full</DebugType>`);
    file.writefln(`    <Optimize>false</Optimize>`);
    file.writefln(`    <DefineConstants>DEBUG;TRACE</DefineConstants>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <PropertyGroup Condition=" '$(Configuration)' == 'Release'">`);
    file.writefln(`    <DebugType>pdbonly</DebugType>`);
    file.writefln(`    <Optimize>true</Optimize>`);
    file.writefln(`    <DefineConstants>TRACE</DefineConstants>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <ItemGroup>`);
    //file.writefln(`    <Reference Include="System" />`);
    //file.writefln(`    <Reference Include="System.Core" />`);
    foreach (ref_; refs)
    {
        file.writefln(`    <Reference Include="%s" />`, ref_);
    }
    foreach (dllFile; dllFileRefs)
    {
        file.writefln(`    <Reference Include="%s">`, dllFile.baseName.stripExtension);
        file.writefln(`        <SpecificVersion>False</SpecificVersion>`);
        if (dllFile.canFind("/", "\\"))
        {
            file.writefln(`        <HintPath>%s</HintPath>`, dllFile);
        }
        file.writefln(`    </Reference>`);
    }
    file.writefln(`  </ItemGroup>`);
    file.writefln(`  <ItemGroup>`);
    foreach (source; sources)
    {
        file.writefln(`    <Compile Include="%s" />`, source);
    }
    file.writefln(`  </ItemGroup>`);
    file.writefln(`  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />`);
    file.writefln(`</Project>`);
}
void writeCsprojUser2008(File file)
{
    file.writefln(`<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">`);
    file.writefln(`  <PropertyGroup>`);
    file.writefln(`    <ReferencePath>C:\Program Files\Mono\lib\mono\4.5\</ReferencePath>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`</Project>`);
}
void writeCsproj2017(File file, string exeName, string uuid, const string[] refs, const string[] dllFileRefs, const string[] sources)
{
    file.writefln(`<?xml version="1.0" encoding="utf-8"?>`);
    file.writefln(`<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">`);
    file.writefln(`  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />`);
    file.writefln(`  <PropertyGroup>`);
    file.writefln(`    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>`);
    file.writefln(`    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>`);
    file.writefln(`    <ProjectGuid>{%s}</ProjectGuid>`, uuid);
    file.writefln(`    <OutputType>Exe</OutputType>`);
    //file.writefln(`    <RootNamespace>ConsoleApp1</RootNamespace>`);
    file.writefln(`    <AssemblyName>%s</AssemblyName>`, exeName);
    file.writefln(`    <TargetFrameworkVersion>v4.6.1</TargetFrameworkVersion>`);
    file.writefln(`    <FileAlignment>512</FileAlignment>`);
    file.writefln(`    <AutoGenerateBindingRedirects>true</AutoGenerateBindingRedirects>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">`);
    file.writefln(`    <PlatformTarget>AnyCPU</PlatformTarget>`);
    file.writefln(`    <DebugSymbols>true</DebugSymbols>`);
    file.writefln(`    <DebugType>full</DebugType>`);
    file.writefln(`    <Optimize>false</Optimize>`);
    file.writefln(`    <OutputPath>bin\Debug\</OutputPath>`);
    file.writefln(`    <DefineConstants>DEBUG;TRACE</DefineConstants>`);
    file.writefln(`    <ErrorReport>prompt</ErrorReport>`);
    file.writefln(`    <WarningLevel>4</WarningLevel>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">`);
    file.writefln(`    <PlatformTarget>AnyCPU</PlatformTarget>`);
    file.writefln(`    <DebugType>pdbonly</DebugType>`);
    file.writefln(`    <Optimize>true</Optimize>`);
    file.writefln(`    <OutputPath>bin\Release\</OutputPath>`);
    file.writefln(`    <DefineConstants>TRACE</DefineConstants>`);
    file.writefln(`    <ErrorReport>prompt</ErrorReport>`);
    file.writefln(`    <WarningLevel>4</WarningLevel>`);
    file.writefln(`  </PropertyGroup>`);
    file.writefln(`  <ItemGroup>`);
    foreach (ref_; refs)
    {
        file.writefln(`    <Reference Include="%s" />`, ref_);
    }
    foreach (dllFile; dllFileRefs)
    {
        file.writefln(`    <Reference Include="%s">`, dllFile.baseName.stripExtension);
        if (dllFile.canFind("/", "\\"))
        {
            file.writefln(`        <HintPath>%s</HintPath>`, dllFile);
        }
        file.writefln(`    </Reference>`);
    }
    file.writefln(`  </ItemGroup>`);
    file.writefln(`  <ItemGroup>`);
    foreach (source; sources)
    {
        file.writefln(`    <Compile Include="%s" />`, source);
    }
    file.writefln(`  </ItemGroup>`);
    file.writefln(`  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />`);
    file.writefln(`</Project>`);
}