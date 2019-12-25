using ManyConsole;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace CodeTool
{
    class GetFunctionsCmd : ConsoleCommand
    {
        private class FullClassNameEqualityComparer : IEqualityComparer<List<string>>
        {
            public static readonly IEqualityComparer<List<string>> Default = new FullClassNameEqualityComparer();

            public bool Equals(List<string> x, List<string> y) => x.SequenceEqual(y);

            public int GetHashCode(List<string> obj) => obj == null ? 0 : obj.Aggregate(0, (acc, item) => acc ^ item.GetHashCode());
        }

        private string m_input;
        private bool m_all;

        public GetFunctionsCmd()
        {
            IsCommand("get-functions", "Returns all the functions in the input file/folder as json.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
            HasOption("all", "Return all the functions, even empty and throw only.", _ => m_all = true);
        }

        public override int Run(string[] remainingArguments)
        {
            var finalRes = new Dictionary<string, Dictionary<string, List<string>>>();
            var res = new Dictionary<string, Dictionary<List<string>, List<(string, uint)>>>();
            foreach (var file in Program.EnumerateInputFiles(m_input))
            {
                Dictionary<List<string>, List<(string Name, uint Crc32)>> fileRes = res[file] = new Dictionary<List<string>, List<(string, uint)>>(FullClassNameEqualityComparer.Default);

                var text = File.ReadAllText(file);
                var tree = CSharpSyntaxTree.ParseText(text);
                var syntaxRoot = tree.GetRoot();
                foreach (var node in syntaxRoot.DescendantNodes())
                {
                    switch (node)
                    {
                    case BaseMethodDeclarationSyntax m:
                        if (!m_all && m.Parent is InterfaceDeclarationSyntax)
                        {
                            continue;
                        }
                        if (m_all || m.Body.HasStatements() || m.ExpressionBody?.Expression.HasCode() == true)
                        {
                            var funcs = GetFuncList(fileRes, m.Parent as TypeDeclarationSyntax);
                            funcs.Add(m.FullName());
                        }
                        break;
                    case PropertyDeclarationSyntax p:
                        if (!m_all && p.Parent is InterfaceDeclarationSyntax)
                        {
                            continue;
                        }
                        if (p.AccessorList != null)
                        {
                            foreach (var a in p.AccessorList.Accessors)
                            {
                                if (m_all || a.Body.HasStatements() || a.ExpressionBody?.Expression.HasCode() == true)
                                {
                                    var funcs = GetFuncList(fileRes, p.Parent as TypeDeclarationSyntax);
                                    funcs.Add(($"{a.Keyword}:{p.Identifier}", 0));
                                }
                            }
                        }
                        else if (m_all || p.ExpressionBody?.Expression.HasCode() == true)
                        {
                            var funcs = GetFuncList(fileRes, p.Parent as TypeDeclarationSyntax);
                            funcs.Add((p.Identifier.Text, 0));
                        }
                        break;
                    }
                }

                if (fileRes.Count > 0)
                {
                    finalRes[file] = fileRes.ToDictionary
                        (
                            kvp => string.Join(".", Enumerable.Reverse(kvp.Key)),
                            kvp => kvp.Value.Select(o => GetFunctionName(o, kvp.Value)).ToList()
                        );
                }
            }
            Console.WriteLine(JsonConvert.SerializeObject(finalRes, Formatting.Indented));
            return 0;
        }

        private static string GetFunctionName((string Name, uint Crc32) cur, List<(string Name, uint Crc32)> all)
        {
            return cur.Crc32 == 0 || all.Count(o => o.Name == cur.Name) == 1 
                ? cur.Name
                : $"{cur.Name}\\{cur.Crc32}";
        }

        private List<(string, uint)> GetFuncList(Dictionary<List<string>, List<(string, uint)>> fileRes, TypeDeclarationSyntax type)
        {
            var fullClassName = new List<string>();
            string className;
            while ((className = GetTypeName(type)) != null)
            {
                fullClassName.Add(className);
                type = type.Parent as TypeDeclarationSyntax;
            }
            if (!fileRes.TryGetValue(fullClassName, out var funcs))
            {
                fileRes[fullClassName] = funcs = new List<(string, uint)>();
            }

            return funcs;
        }

        private string GetTypeName(TypeDeclarationSyntax type)
        {
            if (type == null)
            {
                return null;
            }
            if (type.TypeParameterList == null)
            {
                return type.Identifier.Text;
            }
            return $"{type.Identifier}{type.TypeParameterList}";
        }
    }
}
