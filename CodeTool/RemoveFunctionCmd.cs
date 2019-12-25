using ManyConsole;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeTool
{
    class RemoveFunctionCmd : ConsoleCommand
    {
        private string m_input;
        private string[] m_className;
        private (string Name, uint Crc32) m_functionName;
        private string m_keyword;

        public RemoveFunctionCmd()
        {
            IsCommand("remove-function", "Remove the given function from the given class.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
            HasRequiredOption("c=", "Class name", v => m_className = v.Split('.'));
            HasRequiredOption("f=", "Function name", v => (m_keyword, m_functionName) = NullifyFunctionCmd.ParseFunctionName(v));
        }

        public override int Run(string[] remainingArguments) => Program.Run(Program.EnumerateInputFiles(m_input), RemoveFunction);

        private StringBuilder RemoveFunction(string file)
        {
            var text = File.ReadAllText(file);
            var tree = CSharpSyntaxTree.ParseText(text);
            var syntaxRoot = tree.GetRoot();
            var node = syntaxRoot
                .DescendantNodes()
                .OfType<TypeDeclarationSyntax>()
                .Where(o => RemoveFieldCmd.IsType(m_className, o))
                .SelectMany(c => c
                    .DescendantNodes()
                    .Select(o => NullifyFunctionCmd.GetFunctionNode(o, m_functionName, m_keyword, true))
                    .Where(f => f != null))
                .FirstOrDefault();

            if (node == null)
            {
                return null;
            }

            var sb = new StringBuilder(text);
            if (node.Parent is AccessorListSyntax al && al.Accessors.Count == 1)
            {
                node = al.Parent;
            }
            sb.Remove(node.Span.Start, node.Span.Length);
            return sb;
        }
    }
}
