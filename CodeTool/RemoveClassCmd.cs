using ManyConsole;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeTool
{
    class RemoveClassCmd : ConsoleCommand
    {
        private string m_input;
        private string[] m_className;

        public RemoveClassCmd()
        {
            IsCommand("remove-class", "Remove the given class.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
            HasRequiredOption("c=", "Class name", v => m_className = v.Split('.'));
        }

        public override int Run(string[] remainingArguments) => Program.Run(Program.EnumerateInputFiles(m_input), RemoveClass);

        private StringBuilder RemoveClass(string file)
        {
            var text = File.ReadAllText(file);
            var tree = CSharpSyntaxTree.ParseText(text);
            var syntaxRoot = tree.GetRoot();
            var node = syntaxRoot
                .DescendantNodes()
                .OfType<TypeDeclarationSyntax>()
                .FirstOrDefault(o => RemoveFieldCmd.IsType(m_className, o));

            if (node == null)
            {
                return null;
            }

            var sb = new StringBuilder(text);
            sb.Remove(node.Span.Start, node.Span.Length);
            return sb;
        }
    }
}
