// Generates D code to call C# code using the ClrBridge library
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;

// TODO: maybe provide a way to configure assembly name to D package name map?
//       if I provide any configuration options, they should probably be in a file
//       and I would need to make sure that all .NET assemblies that have been translated
//       have the SAME configuration.  I might be able to verify this somehow?


static class ClrBridgeCodegen
{
    static void Usage()
    {
        Console.WriteLine("Usage: ClrBridgeCodegen.exe <DotNetAssembly> <OutputDir>");
    }
    public static Int32 Main(String[] args)
    {
        if (args.Length != 2)
        {
            Usage();
            return 1;
        }
        String assemblyString = args[0];
        String outputDir = args[1];
        Console.WriteLine("assembly : {0}", assemblyString);
        Console.WriteLine("outputDir: {0}", outputDir);

        Assembly assembly = Assembly.Load(assemblyString);
        new Generator(assembly, outputDir).GenerateModule(assembly);
        return 0;
    }
}

class Generator
{
    readonly Assembly thisAssembly;
    readonly String outputDir;
    readonly Dictionary<Assembly, ExtraAssemblyInfo> assemblyInfoMap;
    readonly Dictionary<String,DModule> moduleMap;
    readonly String thisAssemblyPackageName; // cached version of GetExtraAssemblyInfo(thisAssembly).packageName
    // bool lowercaseModules;

    public Generator(Assembly thisAssembly, String outputDir)
    {
        this.thisAssembly = thisAssembly;
        this.outputDir = outputDir;
        this.assemblyInfoMap = new Dictionary<Assembly,ExtraAssemblyInfo>();
        this.moduleMap = new Dictionary<String,DModule>();
        this.thisAssemblyPackageName = GetExtraAssemblyInfo(thisAssembly).packageName;
    }

    ExtraAssemblyInfo GetExtraAssemblyInfo(Assembly assembly)
    {
        ExtraAssemblyInfo info;
        if (!assemblyInfoMap.TryGetValue(assembly, out info))
        {
            info = new ExtraAssemblyInfo(
                assembly.GetName().Name.Replace(".", "_")
            );
            assemblyInfoMap[assembly] = info;
        }
        return info;
    }

    public void GenerateModule(Assembly assembly)
    {
        foreach (Type type in assembly.GetTypes())
        {
            //writer.WriteLine("type {0}", type);

            DModule module;
            if (!moduleMap.TryGetValue(type.Namespace.NullToEmpty(), out module))
            {
                // TODO: make directories
                String outputDFilename = Path.Combine(outputDir,
                    Path.Combine(thisAssemblyPackageName, Util.NamespaceToModulePath(type.Namespace)));
                Console.WriteLine("[DEBUG] NewDModule '{0}'", outputDFilename);
                Directory.CreateDirectory(Path.GetDirectoryName(outputDFilename));
                StreamWriter writer = new StreamWriter(new FileStream(outputDFilename, FileMode.Create, FileAccess.Write, FileShare.Read));
                // TODO: modify if lowercaseModules
                String moduleFullName = thisAssemblyPackageName;
                if (type.Namespace.NullToEmpty().Length > 0)
                    moduleFullName = String.Format("{0}.{1}", thisAssemblyPackageName, type.Namespace);
                module = new DModule(moduleFullName, writer);
                writer.WriteLine("module {0};", moduleFullName);
                writer.WriteLine("");
                writer.WriteLine("// Keep D Symbols inside the __d struct to prevent symbol conflicts");
                writer.WriteLine("struct __d");
                writer.WriteLine("{");
                writer.WriteLine("    import cstring : CString, CStringLiteral;");
                writer.WriteLine("    static import dotnet;");
                writer.WriteLine("    static import clrbridge;");
                writer.WriteLine("    import clrbridgeglobal : globalClrBridge;");
                writer.WriteLine("    alias ObjectArray = clrbridge.Array!(dotnet.PrimitiveType.Object);");
                writer.WriteLine("}");
                moduleMap.Add(type.Namespace.NullToEmpty(), module);
            }

/*
            const String InvalidChars = "<=`";
            bool foundInvalidChar = false;
            foreach (Char invalidChar in InvalidChars)
            {
                if (type.Name.Contains(invalidChar))
                {
                    Message(module, "skipping type {0} because it contains '{1}'", type.Name, invalidChar);
                    foundInvalidChar = true;
                    break;
                }
            }
            if (foundInvalidChar)
                continue;
*/
            if (type.IsGenericType)
            {
                Message(module, "skipping type {0} because generics aren't implemented", type.Name);
                continue;
            }

            if (type.IsValueType)
            {
                if (type.IsEnum)
                {
                    GenerateEnum(module, type);
                }
                else
                {
                    GenerateStruct(module, type);
                }
            }
            else if (type.IsInterface)
            {
                GenerateInterface(module, type);
            }
            else
            {
                Debug.Assert(type.IsClass);
                if (typeof(Delegate).IsAssignableFrom(type))
                {
                    GenerateDelegate(module, type);
                }
                else
                {
                    GenerateClass(module, type);
                }
            }
        }
        foreach (DModule module in moduleMap.Values)
        {
            module.writer.Close();
        }
    }

    void Message(DModule module, String fmt, params Object[] args)
    {
        String message = String.Format(fmt, args);
        Console.WriteLine(message);
        module.writer.WriteLine("// {0}", message);
    }

    void GenerateEnum(DModule module, Type type)
    {
        module.writer.WriteLine("enum {0}", Util.GetTypeName(type));
        module.writer.WriteLine("{");
        module.writer.WriteLine("    placeholder, // TODO: generate actual values");
        //GenerateFields(module, type);
        //GenerateMethods(module, type);
        module.writer.WriteLine("}");
    }

    void GenerateStruct(DModule module, Type type)
    {
        module.writer.WriteLine("struct {0}", Util.GetTypeName(type));
        module.writer.WriteLine("{");
        GenerateFields(module, type);
        GenerateMethods(module, type);
        module.writer.WriteLine("}");
    }
    void GenerateInterface(DModule module, Type type)
    {
        module.writer.WriteLine("interface {0}", Util.GetTypeName(type));
        module.writer.WriteLine("{");
        Debug.Assert(type.GetFields().Length == 0);
        GenerateMethods(module, type);
        module.writer.WriteLine("}");
    }
    void GenerateDelegate(DModule module, Type type)
    {
        module.writer.WriteLine("// TODO: generate delegate '{0}'", Util.GetTypeName(type));
    }
    void GenerateClass(DModule module, Type type)
    {
        if (type.DeclaringType != null)
        {
            module.writer.WriteLine("// DeclaringType = {0}", Util.GetTypeName(type.DeclaringType));
        }
        module.writer.WriteLine("class {0}", Util.GetTypeName(type));
        module.writer.WriteLine("{");
        GenerateFields(module, type);
        GenerateMethods(module, type);
        module.writer.WriteLine("}");
    }

    void GenerateFields(DModule module, Type type)
    {
        foreach (FieldInfo field in type.GetFields())
        {
            Type fieldType = field.FieldType;
            String fromDll = (fieldType.Assembly == thisAssembly) ? "" :
                GetExtraAssemblyInfo(fieldType.Assembly).fromDllPrefix;
            module.writer.WriteLine("    {0} {1}; // fromPrefix '{2}' {3} {4}",
                ToDType(fieldType),
                field.Name.ToDIdentifier(),
                fromDll,
                field.FieldType, field.FieldType.AssemblyQualifiedName);
        }
    }

    void GenerateMethods(DModule module, Type type)
    {
        foreach (MethodInfo method in type.GetMethods())
        {
            //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            // skip virtual methods for now so we don't get linker errors
            if (method.IsVirtual)
                continue;

            module.writer.Write("    {0}", method.IsPrivate ? "private" : "public");
            if (method.IsStatic)
            {
                module.writer.Write(" static");
            }
            else if (method.IsFinal)
            {
                module.writer.Write(" final");
            }

            Debug.Assert(method.ReturnType != null);
            if (method.ReturnType == typeof(void))
                module.writer.Write(" void");
            else
                module.writer.Write(" {0}", ToDType(method.ReturnType));
            module.writer.Write(" {0}", Util.ToDIdentifier(method.Name));
            //
            // TODO: generate generic parameters
            //
            module.writer.Write("(");
            ParameterInfo[] parameters = method.GetParameters();
            {
                string prefix = "";
                foreach (ParameterInfo parameter in parameters)
                {
                    module.writer.Write("{0}{1} {2}", prefix, ToDType(parameter.ParameterType), Util.ToDIdentifier(parameter.Name));
                    prefix = ", ";
                }
            }
            module.writer.Write(")");
            if (method.IsVirtual)
            {
                module.writer.WriteLine(";");
                continue;
            }
            module.writer.WriteLine();
            module.writer.WriteLine("    {");
            GenerateMethodBody(module, type, method, parameters);
            // placeholder for returning a valid value
            if (method.ReturnType != typeof(void))
            {
                module.writer.WriteLine("        return {0}.init;", ToDType(method.ReturnType));
            }
            module.writer.WriteLine("    }");
        }
    }

    void GenerateMethodBody(DModule module, Type type, MethodInfo method, ParameterInfo[] parameters)
    {
        // skip non-static methods for now, they just take too long right now
        if (!method.IsStatic)
            return;

        // TODO: we may want to cache some of this stuff, but for now we'll just get it

        // Get Assembly so we can get Type then Method (TODO: cache this somehow?)
        Util.GenerateTypeGetter(module.writer, "        ", type, "__this_assembly__", "__this_type__");
        module.writer.WriteLine("        auto  __method__ = __d.clrbridge.MethodInfo.nullObject;");
        module.writer.WriteLine("        scope (exit) { if (!__method__.isNull) __d.globalClrBridge.release(__method__); }");

        //
        // Get Method
        //
        // NOTE: it isn't necessary to create a type array to get the method if there is only
        //       one method with that name, this is an optimization case that can be done later
        // if (hasOverloads)
        module.writer.WriteLine("        {");
        {
            uint paramIndex = 0;
            foreach (ParameterInfo parameter in parameters)
            {
                Util.GenerateTypeGetter(module.writer, "            ", parameter.ParameterType,
                    String.Format("__param{0}_assembly__", paramIndex),
                    String.Format("__param{0}_type__", paramIndex));
                paramIndex++;
            }
            module.writer.WriteLine("            __method__ = __d.globalClrBridge.getMethod(__this_type__,");
            module.writer.WriteLine("                __d.CStringLiteral!\"{0}\",", method.Name);
            module.writer.WriteLine("                __d.globalClrBridge.makeGenericArray(__d.globalClrBridge.typeType");
            for (uint i = 0; i < parameters.Length; i++)
            {
                module.writer.WriteLine("                , __param{0}_type__", i);
            }
            module.writer.WriteLine("                ));");
        }
        module.writer.WriteLine("        }");

        //
        // Create parameters ObjectArray
        //
        {
            uint paramIndex = 0;
            foreach (ParameterInfo parameter in parameters)
            {
                if (parameter.ParameterType.IsArray ||
                    parameter.ParameterType.IsByRef ||
                    parameter.ParameterType.IsPointer)
                {
                    // skip complicated types for now
                }
                else
                {
                    String boxType = TryGetBoxType(parameter.ParameterType);
                    if (boxType != null)
                    {
                        module.writer.WriteLine("        auto  __param{0}__ = __d.globalClrBridge.box!(__d.dotnet.PrimitiveType.{1})({2}); // actual type is {3}",
                            paramIndex, boxType, Util.ToDIdentifier(parameter.Name), Util.GetTypeName(parameter.ParameterType));
                        module.writer.WriteLine("        scope (exit) __d.globalClrBridge.release(__param{0}__);", paramIndex);
                    }
                }
                paramIndex++;
            }
        }
        module.writer.WriteLine("        __d.ObjectArray __param_values__ = __d.globalClrBridge.makeObjectArray(");
        {
            uint paramIndex = 0;
            string prefix = " ";
            foreach (ParameterInfo parameter in parameters)
            {
                if (TryGetBoxType(parameter.ParameterType) != null)
                    module.writer.WriteLine("            {0}__param{1}__", prefix, paramIndex);
                else
                    module.writer.WriteLine("            {0}{1}", prefix, Util.ToDIdentifier(parameter.Name));
                prefix = ",";
                paramIndex++;
            }
        }
        module.writer.WriteLine("        );");
        module.writer.WriteLine("        scope (exit) { __d.globalClrBridge.release(__param_values__); }");
        module.writer.WriteLine("        __d.globalClrBridge.funcs.CallGeneric(__method__, __d.dotnet.DotNetObject.nullObject, __param_values__);");
    }

    // TODO: add TypeContext?  like fieldDecl?  Might change const(char)* to string in some cases?
    string ToDType(Type type)
    {
        Debug.Assert(type != typeof(void)); // not handled yet
        if (type == typeof(Boolean)) return "bool";
        if (type == typeof(Byte))    return "ubyte";
        if (type == typeof(SByte))   return "byte";
        if (type == typeof(UInt16))  return "ushort";
        if (type == typeof(Int16))   return "short";
        if (type == typeof(UInt32))  return "uint";
        if (type == typeof(Int32))   return "int";
        if (type == typeof(UInt64))  return "ulong";
        if (type == typeof(Int64))   return "long";
        if (type == typeof(Char))    return "char";
        if (type == typeof(String))  return "__d.CString";
        if (type == typeof(Single))  return "float";
        if (type == typeof(Double))  return "double";
        if (type == typeof(Decimal)) return "__d.dotnet.Decimal";
        if (type == typeof(Object))  return "__d.dotnet.DotNetObject";
        //String fromDll = (fieldType.Assembly == thisAssembly) ? "" :
        //    GetExtraAssemblyInfo(fieldType.Assembly).fromDllPrefix;
        return "__d.dotnet.DotNetObject";
    }
    static String TryGetBoxType(Type type)
    {
        Debug.Assert(type != typeof(void)); // not handled yet
        if (type == typeof(Boolean)) return "Boolean";
        if (type == typeof(Byte))    return "Byte";
        if (type == typeof(SByte))   return "SByte";
        if (type == typeof(UInt16))  return "UInt16";
        if (type == typeof(Int16))   return "Int16";
        if (type == typeof(UInt32))  return "UInt32";
        if (type == typeof(Int32))   return "Int32";
        if (type == typeof(UInt64))  return "UInt64";
        if (type == typeof(Int64))   return "Int64";
        if (type == typeof(Char))    return "Char";
        if (type == typeof(String))  return "String";
        if (type == typeof(Single))  return "Single";
        if (type == typeof(Double))  return "Double";
        if (type == typeof(Decimal)) return "Decimal";
        if (type == typeof(Object))  return null;
        return null;
    }
}

class DModule
{
    public readonly String fullName;
    public readonly StreamWriter writer;
    public DModule(String fullName, StreamWriter writer)
    {
        this.fullName = fullName;
        this.writer = writer;
    }
}

class ExtraAssemblyInfo
{
    public readonly string packageName;
    public readonly string fromDllPrefix;
    public ExtraAssemblyInfo(string packageName)
    {
        this.packageName = packageName;
        this.fromDllPrefix = String.Format("fromDll!\"{0}\".", packageName);
    }
}

static class Util
{
    public static String NamespaceToModulePath(String @namespace)
    {
        String path = "";
        if (@namespace != null)
        {
            foreach (String part in @namespace.Split('.'))
            {
                path = Path.Combine(path, part);
            }
        }
        return Path.Combine(path, "package.d");
    }
    // add a trailing '_' to keywords
    public static String ToDIdentifier(this String s)
    {
        if (s == "align") return "align_";
        if (s == "module") return "module_";
        if (s == "version") return "version_";
        if (s == "function") return "function_";
        if (s == "scope") return "scope_";
        if (s == "asm") return "asm_";
        if (s == "lazy") return "lazy_";
        return s
            .Replace("$", "_")
            .Replace("<", "_")
            .Replace(">", "_")
            .Replace("=", "_")
            .Replace("`", "_");
    }
    // rename types that conflict with standard D types
    public static String GetTypeName(Type type)
    {
        // A hack for now, we should probably just generate the code for each type like
        // this inside the DeclaringType
        string prefix = "";
        if (type.DeclaringType != null)
        {
            prefix = "InsideOf_" + GetTypeName(type.DeclaringType) + "_";
        }
        if (type.Name == "Object")
            return prefix + "DotNetObject";
        if (type.Name == "Exception")
            return prefix + "DotNetException";
        if (type.Name == "TypeInfo")
            return prefix + "DotNetTypeInfo";
        return prefix + type.Name
            .Replace("$", "_")
            .Replace("<", "_")
            .Replace(">", "_")
            .Replace("=", "_")
            .Replace("`", "_");
    }

    public static void GenerateTypeGetter(StreamWriter writer, String linePrefix, Type type, String assemblyVarname, String typeVarname)
    {
        writer.WriteLine("{0}const  {1} = __d.globalClrBridge.loadAssembly(__d.CStringLiteral!\"{2}\");", linePrefix, assemblyVarname, type.Assembly.FullName);
        writer.WriteLine("{0}scope (exit) __d.globalClrBridge.release({1});", linePrefix, assemblyVarname);
        writer.WriteLine("{0}const  {1} = __d.globalClrBridge.getType({2}, __d.CStringLiteral!\"{3}\");", linePrefix, typeVarname, assemblyVarname, type.FullName);
        writer.WriteLine("{0}scope (exit) __d.globalClrBridge.release({1});", linePrefix, typeVarname);
    }
}

static class Extensions
{
    public static String NullToEmpty(this String s)
    {
       return (s == null) ? "" : s;
    }
}
