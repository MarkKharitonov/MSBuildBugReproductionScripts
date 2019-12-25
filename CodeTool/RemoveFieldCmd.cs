using ManyConsole;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeTool
{
    class RemoveFieldCmd : ConsoleCommand
    {
        private string m_input;
        private string[] m_className;
        private string m_fieldName;

        public RemoveFieldCmd()
        {
            IsCommand("remove-field", "Remove the given field/event from the given class.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
            HasRequiredOption("c=", "Class name", v => m_className = v.Split('.'));
            HasRequiredOption("f=", "Field name", v => m_fieldName = v);
        }

        public override int Run(string[] remainingArguments) => Program.Run(Program.EnumerateInputFiles(m_input), RemoveField);

        private StringBuilder RemoveField(string file)
        {
            var count = 0;
            var text = File.ReadAllText(file);
            var sb = new StringBuilder(text);
            var tree = CSharpSyntaxTree.ParseText(text);
            var syntaxRoot = tree.GetRoot();
            foreach (var node in syntaxRoot
                .DescendantNodes()
                .OfType<ClassDeclarationSyntax>()
                .Where(o => IsType(m_className, o))
                .SelectMany(c => c
                    .DescendantNodes()
                    .OfType<BaseFieldDeclarationSyntax>()
                    .Where(o => o.Declaration.Variables.Any(v => v.Identifier.Text == m_fieldName)))
                .OrderByDescending(f => f.Span.End))
            {
                sb.Remove(node.Span.Start, node.Span.Length);
                ++count;
            }
            return count == 0 ? null : sb;
        }

        public static bool IsType(string[] typeName, TypeDeclarationSyntax type)
        {
            int i = -1;
            for (i = typeName.Length - 1; i >= 0 && IsType(typeName[i], type); --i)
            {
                type = type.Parent as TypeDeclarationSyntax;
            }
            return i == -1;
        }

        private static bool IsType(string typeName, TypeDeclarationSyntax type)
        {
            if (type == null)
            {
                return false;
            }
            if (typeName.IndexOf('<') < 0)
            {
                return type.Identifier.Text == typeName;
            }
            if (type.TypeParameterList == null)
            {
                return false;
            }
            return $"{type.Identifier}{type.TypeParameterList}" == typeName;
        }
    }
}
