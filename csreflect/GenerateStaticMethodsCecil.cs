using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

using Mono.Cecil;
using Mono.Cecil.Cil;
using Mono.CompilerServices.SymbolWriter;
using System.Reflection;

using System.IO;
using System.Runtime.InteropServices;

static class MainClass
{
    public static int Main(string[] args)
    {
        if (args.Length >= 3)
        {
            string baseName = args[0];
            string inputDir = args[1];
            string outputDir = args[2];
            if (args.Length <= 3)
            {
                Assembly assembly = Assembly.LoadFile(Path.Combine(inputDir, baseName, baseName + ".dll"));
                string outputDFile = Path.Combine(outputDir, baseName.ToLower() + ".d");
                using (StreamWriter dwrapper = new StreamWriter(new FileStream(outputDFile, FileMode.Create, FileAccess.Write, FileShare.Read)))
                {
                    CLRBuilder builder = new CLRBuilder(baseName, dwrapper);
                    ModuleDefinition moduleDef = builder.Run(assembly);
                    moduleDef.Write(Path.Combine(outputDir, baseName + "static.dll"));
                }
                return 0;
            }
        }
        Console.WriteLine("Usage: csreflect NAME INPUT_DIR OUTPUT_DIR");
        return 1;
    }
}

class CLRBuilder
{
    private readonly string baseName;
    private readonly string baseNameLower;
    private readonly StreamWriter dwrapper; // output .d file
    private readonly bool useClass;
    private readonly ModuleDefinition moduleDef;

    public CLRBuilder(string baseName, StreamWriter dwrapper)
    {
        this.baseName = baseName;
        this.baseNameLower = baseName.ToLower();
        this.dwrapper = dwrapper;
        this.useClass = false;
        var resolver = new DefaultAssemblyResolver();
        //resolver.AddSearchDirectory(Directory.GetCurrentDirectory());
        this.moduleDef = ModuleDefinition.CreateModule(baseName + "static",
            new ModuleParameters { Kind = ModuleKind.Dll, AssemblyResolver = resolver });
    }

    public ModuleDefinition Run(Assembly assembly)
    {
        dwrapper.Write("module " + baseNameLower + ";\n");
        dwrapper.Write("import dflat.wrap;\nimport dflat.types;\nimport dflat.host;\nimport core.memory : GC;\n");
        if (useClass)
        {
            dwrapper.Write("@DLL(\"" + baseName + "\")\n");
            dwrapper.Write("{\n");
        }

        // To avoid duplicately adding types
        //HashSet<String> visitedTypes = new HashSet<String>();

        foreach (Type type in assembly.GetExportedTypes())
        {
            /*
            //Assume that duplicates are identical (e.g. interface / class pairs)
            if (visitedTypes.Contains(type.Name))
            {
                // TODO: does this happen?
                //       Having the same name does not necessarily mean they are the same type??
                //       what about fully-qualified name?  assembly? etc.
                Console.WriteLine("visiting duplcated type '{0}'", type.Name);
                continue;
            }
            visitedTypes.Add(type.Name);
            */

            Console.WriteLine("Type '{0}'", type.Name);

            //TODO: support namespaces
            WriteAggHdr(dwrapper, useClass, type);
            TypeDefinition typedef = new TypeDefinition(type.Namespace,
                                    type.Name + "static",
                                    Mono.Cecil.TypeAttributes.Public,
                                    moduleDef.ImportReference(typeof(object)) /*base class*/);

            // To avoid duplicately adding methods (TODO: address this)
            HashSet<String> visitedMethods = new HashSet<String>();
            foreach (MemberInfo mi in type.GetMembers())
            {
                if (visitedMethods.Contains(mi.Name)) continue;
                visitedMethods.Add(mi.Name);
                // Sanity check:
                // If you think you are missing methods make sure they are public!
                // Console.WriteLine(mi.Name);
                if (mi.Name == "assert")
                    continue;

                if (mi.MemberType == MemberTypes.Method)
                {
                    MethodDefinition methodDef = TryCreateMethod(type, (MethodInfo)mi);
                    if (methodDef != null)
                        typedef.Methods.Add(methodDef);
                }
                else if (mi.MemberType == MemberTypes.Constructor)
                    AddCtor(type, typedef, (ConstructorInfo)mi);
                else if (mi.MemberType == MemberTypes.Property)
                {
                    // Already handled with addMethod above
                }
            }

            moduleDef.Types.Add(typedef);
            dwrapper.Write("}\n");
        }
        return moduleDef;
    }

    static void WriteAggHdr(StreamWriter dwrapper, bool useClass, Type type)
    {
        if (useClass)
            dwrapper.Write("abstract class ");
        else
            dwrapper.Write("struct ");
        dwrapper.Write(type.Name); dwrapper.Write("\n{\n");
        if (!useClass)
        {
            dwrapper.Write("    Instance!(\"" + type.Name + "\") _raw;\n    alias _raw this;\n\n");
        }
        dwrapper.Write("    import core.memory : GC;\n");
    }

    static void WriteMethodParams(StreamWriter dwrapper, bool isStatic, string retTy, Type[] paramTypes)
    {
        dwrapper.Write("("+ retTy + ((retTy != "" && paramTypes.Length >= 1)? ", " : ""));
        if (isStatic)
        {
            if (paramTypes.Length > 0)
            {
                foreach (Type pt in paramTypes.Skip(1).Take(paramTypes.Length - 2))
                {
                    dwrapper.Write(ToDType(pt));
                    dwrapper.Write(", ");
                }
                dwrapper.Write(ToDType(paramTypes[paramTypes.Length - 1]));
            }
        }
        else
        {
            if (paramTypes.Length >= 1) dwrapper.Write(ToDType(paramTypes[0]));
            if (paramTypes.Length > 1) foreach (Type pt in paramTypes.Skip(1).Take(paramTypes.Length))
            {
                dwrapper.Write(", ");
                dwrapper.Write(ToDType(pt));
            }
        }
        dwrapper.Write(")");
    }
    void WriteDMethod(Type type, bool isStatic, bool prop,string retTy,string name, Type[] tps, string altName)
    {
        dwrapper.Write("    ");
        if (useClass)
            dwrapper.Write("abstract ");
        if (isStatic && !useClass)
            dwrapper.Write("static ");
        if (prop)
            dwrapper.Write("@property ");

        string methName = (prop) ? name.Substring("get_".Length) : name;
        dwrapper.Write(retTy + " " + methName);

        WriteMethodParams(dwrapper, isStatic,"",tps);

        if (useClass)
        {
            dwrapper.Write(";\n");
            return;
        }
        dwrapper.Write("\n    {\n");

        dwrapper.Write("        alias func = extern(C) " + ((altName != null) ? altName : retTy) + " function");
        WriteMethodParams(dwrapper, isStatic,isStatic ? "" : "void*",tps); dwrapper.Write(";\n");

        dwrapper.Write("        // Avoid the GC stopping a running C# thread.\n");
        dwrapper.Write("        GC.disable; scope(exit) GC.enable;\n");
        dwrapper.Write("        auto f = cast(func)(clrhost.create_delegate(\"" + baseName + "static\",");
        dwrapper.Write("\"" + type.Namespace + (type.Namespace == null ? "" : ".") + type.Name + "static\", \"" + name + "\"));\n");
        if (retTy == "void")
            dwrapper.Write("        return f(");
        else
            dwrapper.Write("        auto ret = f(");
        if (!isStatic)
        {
            dwrapper.Write("_raw" + ((tps.Length >= 1)? ", " : ""));
        }
        if (tps.Length > 0)
        {

            for (int i = 1; i < tps.Length; i++)
            {
                dwrapper.Write("_param_"+(i-1).ToString() + ",");
            }
            dwrapper.Write("_param_" + (tps.Length-1).ToString());
        }
        dwrapper.Write(");\n");
        if (retTy != "void")
            dwrapper.Write("        return *cast("+retTy+"*)&ret;\n");
        dwrapper.Write("    }\n\n");
    }

    MethodDefinition TryCreateMethod(Type type, MethodInfo methodInfo)
    {
        //Generate
        // static mi.ReturnType mi.Name (t this, typeof(mi.GetParameters()) args...)
        //{
        //    return this.(mi.Name)(args);
        //}

        // Need to treat differently
        //    ToString Equals GetHashCode & GetType
        bool isProp = methodInfo.Name.StartsWith("get_") || methodInfo.Name.StartsWith("set_");

        List<Type> tl = new List<Type>();
        //tl.Insert(0, t);
        tl.AddRange(methodInfo.GetParameters().Select(p => p.ParameterType));
        Type[] tps = tl.ToArray();
        string methname;
        if (methodInfo.Name == "ToString")
        {
            //Don't create two methods with the same name
            if (type.GetMethod("toString") != null)
                return null;
            methname = "toString";
        }
        else if (methodInfo.Name == "GetType")
        {
            methname = "getType";
            return null;
        }
        else methname = methodInfo.Name;
        Console.WriteLine("    Method '{0}'", methname);
        var mb = new MethodDefinition(methname,
                                   Mono.Cecil.MethodAttributes.Public |
                                       Mono.Cecil.MethodAttributes.Static,
                                   moduleDef.ImportReference(methodInfo.ReturnType));
        mb.Parameters.Add(new ParameterDefinition(moduleDef.ImportReference(typeof(IntPtr))));
        foreach (Type _t in tps)
        {
            mb.Parameters.Add(new ParameterDefinition(moduleDef.ImportReference(_t)));
        }
        WriteDMethod(type, methodInfo.IsStatic, isProp, ToDType(methodInfo.ReturnType), methname, tps, null);

        {
            var ilg = mb.Body.GetILProcessor();
            ilg.Emit(OpCodes.Nop);
            if (methodInfo.IsStatic)
            {
                EmitArgs(ilg,tps);
                ilg.Emit(OpCodes.Call, moduleDef.ImportReference(methodInfo));
            }
            else
            {
                NewVar(mb, typeof(GCHandle));
                NewVar(mb, typeof(Object));
                NewVar(mb, type);
                if (methodInfo.ReturnType != typeof(void))
                    NewVar(mb, methodInfo.ReturnType);
                moduleDef.ImportReference(typeof(GCHandle));
                ilg.Emit(OpCodes.Ldarg_0);

                MethodReference mr = moduleDef.ImportReference(typeof(GCHandle).GetMethod("FromIntPtr", new[] {typeof(IntPtr)}));
                ilg.Emit(OpCodes.Call, mr);
                ilg.Emit(OpCodes.Stloc_0);
                ilg.Emit(OpCodes.Ldloca_S, mb.Body.Variables[0]);
                ilg.Emit(OpCodes.Call, moduleDef.ImportReference(typeof(GCHandle).GetMethod("get_Target")));
                ilg.Emit(OpCodes.Stloc_1);
                ilg.Emit(OpCodes.Ldloc_1);
                ilg.Emit(OpCodes.Castclass, moduleDef.ImportReference(type));
                ilg.Emit(OpCodes.Stloc_2);
                ilg.Emit(OpCodes.Ldloc_2);
                for (byte x = 0; x < tps.Length; x++)
                {
                    ilg.Emit(OpCodes.Ldarg_S, x);
                }
                ilg.Emit(type.IsSealed ? OpCodes.Call : OpCodes.Callvirt, moduleDef.ImportReference(methodInfo));
                if (methodInfo.ReturnType != typeof(void))
                {
                    ilg.Emit(OpCodes.Stloc_3);
                    ilg.Emit(OpCodes.Ldloc_3);
                }
            }
            ilg.Emit(OpCodes.Ret);
        }
        return mb;
    }

    void AddCtor(Type type, TypeDefinition typedef, ConstructorInfo ci)
    {
        //Generate C#
        // static IntPtr make (typeof(ci.GetParameters()) args...)
        // {
        //    var ret = new t(args);
        //    Object o = (Object)ret;
        //    GCHandle gch = GCHandle.Alloc(o);
        //    return GCHandle.ToIntPtr(gch);
        // }
        // static void unpin(IntPtr pthis)
        //    GCHandle gch = GCHandle.FromIntPtr(pthis);
        //    gch.Free();
        //      return;
        // }
        // Generate D
        //
        // @MethodType.static_ t ___ctor( typeof(ci.GetParameters()) args...)
        Type[] tps = ci.GetParameters().Select(p => p.ParameterType).ToArray();

        WriteDMethod(type, true,  false, type.Name, "make",  tps, "void*");
        WriteDMethod(type, false, false, "void", "unpin", new Type[]{}, null);

        {
            Console.WriteLine("here");
            var mb = new MethodDefinition("make",
                                       Mono.Cecil.MethodAttributes.Public |
                                       Mono.Cecil.MethodAttributes.Static,
                                       moduleDef.ImportReference(typeof(IntPtr)));
            typedef.Methods.Add(mb);
            foreach (Type _t in tps)
                mb.Parameters.Add(new ParameterDefinition(moduleDef.ImportReference(_t)));

            var ilg = mb.Body.GetILProcessor();
            NewVar(mb, typeof(Object));
            NewVar(mb, typeof(GCHandle));
            NewVar(mb, typeof(IntPtr));
            // Copy what ildasm says csc does modulo redundant direct branches
            ilg.Create(OpCodes.Nop);

            EmitArgs(ilg, tps);

            MethodReference mr = moduleDef.ImportReference(ci);
            ilg.Emit(OpCodes.Newobj, mr);

            ilg.Emit(OpCodes.Stloc_0);
            ilg.Emit(OpCodes.Ldloc_0);
            ilg.Emit(OpCodes.Call, moduleDef.ImportReference(typeof(GCHandle).GetMethod("Alloc", new[] { typeof(Object) })));

            ilg.Emit(OpCodes.Stloc_1);
            ilg.Emit(OpCodes.Ldloc_1);
            ilg.Emit(OpCodes.Call, moduleDef.ImportReference(typeof(GCHandle).GetMethod("ToIntPtr")));
            ilg.Emit(OpCodes.Stloc_2);
            ilg.Emit(OpCodes.Ldloc_2);
            ilg.Emit(OpCodes.Ret);
        }
        {
            var mb2 = new MethodDefinition("unpin",
                                      Mono.Cecil.MethodAttributes.Public |
                                      Mono.Cecil.MethodAttributes.Static,
                                      moduleDef.ImportReference(typeof(void)));
            typedef.Methods.Add(mb2);
            mb2.Parameters.Add(new ParameterDefinition(moduleDef.ImportReference(typeof(IntPtr))));

            var ilg2 = mb2.Body.GetILProcessor();
            NewVar(mb2, typeof(GCHandle));

            ilg2.Emit(OpCodes.Nop);
            ilg2.Emit(OpCodes.Ldarg_0);
            ilg2.Emit(OpCodes.Call, moduleDef.ImportReference(typeof(GCHandle).GetMethod("FromIntPtr")));
            ilg2.Emit(OpCodes.Stloc_0);
            ilg2.Emit(OpCodes.Ldloca_S,mb2.Body.Variables[0]);
            ilg2.Emit(OpCodes.Call, moduleDef.ImportReference(typeof(GCHandle).GetMethod("Free")));
            ilg2.Emit(OpCodes.Nop);

            ilg2.Emit(OpCodes.Ret);

        }
    }
    void NewVar(MethodDefinition mb,Type tt)
    {
        mb.Body.Variables.Add(new VariableDefinition(moduleDef.ImportReference(tt)));
    }
    static string ToDType(Type type)
    {
        if (type == typeof(IntPtr))
            return "void*";
        else if (type.IsArray)
        {
            //N.B. the marshaller can't handle nested (i.e. jagged) arrays.
            return "SafeArray!(" + ToDType(type.GetElementType()) + "," + type.GetArrayRank().ToString() + ")";
        }
        else if (type.IsByRef)
        {
            return "ref " + ToDType(type.GetElementType());
        }
        else if (type == typeof(void))
            return "void";
        else if (type == typeof(double))
            return "double";
        else if (type == typeof(int))
            return "int";
        else if (type == typeof(ulong))
            return "ulong";
        else if (type == typeof(string))
            return "const(char)*";
        else if (type == typeof(bool))
            return "bool";
        return "Instance!(\"" + type.Name + "\")";
    }

    static void EmitArgs(ILProcessor ilg, Type[] tps)
    {
        if (tps.Length > 0)
            ilg.Emit(OpCodes.Ldarg_0);
        if (tps.Length > 1)
            ilg.Emit(OpCodes.Ldarg_1);
        if (tps.Length > 2)
            ilg.Emit(OpCodes.Ldarg_2);
        if (tps.Length > 3)
            ilg.Emit(OpCodes.Ldarg_3);
        for (byte x = 4; x < tps.Length; x++)
        {
            ilg.Emit(OpCodes.Ldarg_S, x);
        }
    }

    // https://docs.microsoft.com/en-au/dotnet/standard/native-interop/type-marshaling
    static bool HasMarshalling(Type t)
    {
        if (Array.Exists(MarshalledTypes,
                         e => e == t))
            return true;
        return false;
    }

    static Type[] MarshalledTypes = new Type[] {
        typeof(byte),
        typeof(sbyte),
        typeof(short),
        typeof(ushort),
        typeof(int),
        typeof(uint),
        typeof(long),
        typeof(ulong),
        typeof(char),
        typeof(IntPtr),
        typeof(UIntPtr),
        typeof(bool),
        typeof(decimal),
        typeof(DateTime),
        typeof(Guid),
        typeof(string)
    };
}
