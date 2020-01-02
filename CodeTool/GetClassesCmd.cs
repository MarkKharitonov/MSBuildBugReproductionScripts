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
    class GetClassesCmd : ConsoleCommand
    {
        private string m_input;

        public GetClassesCmd()
        {
            IsCommand("get-classes", "Returns all the classes in the input file/folder as json.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
        }

        public override int Run(string[] remainingArguments)
        {
            var res = Program
                .EnumerateInputFiles(m_input)
                .ToDictionary(
                    file => file,
                    file => CSharpSyntaxTree.ParseText(File.ReadAllText(file))
                        .GetRoot()
                        .DescendantNodes()
                        .OfType<TypeDeclarationSyntax>()
                        .Select(t => string.Join(".", Enumerable.Reverse(GetFunctionsCmd.GetTypeNameParts(t))))
                        .ToList());
            Console.WriteLine(JsonConvert.SerializeObject(res, Formatting.Indented));
            return 0;
        }
    }
}
