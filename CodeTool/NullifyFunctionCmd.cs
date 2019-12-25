using ManyConsole;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeTool
{
    class NullifyFunctionCmd : ConsoleCommand
    {
        private string m_input;
        private string[] m_className;
        private (string Name, uint Crc32) m_functionName;
        private string m_keyword;

        public NullifyFunctionCmd()
        {
            IsCommand("nullify-function", "Nullifies the C# code of the given function by replacing its body with a throw statement.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
            HasRequiredOption("c=", "Class name", v => m_className = v.Split('.'));
            HasRequiredOption("f=", "Function name", v => (m_keyword, m_functionName) = ParseFunctionName(v));
        }

        public static (string, (string, uint)) ParseFunctionName(string v)
        {
            int pos = v.IndexOf(':');
            if (pos > 0)
            {
                return (v.Substring(0, pos), (v.Substring(pos + 1), 0));
            }
            pos = v.IndexOf('\\');
            if (pos > 0)
            {
                return (null, (v.Substring(0, pos), uint.Parse(v.Substring(pos + 1))));
            }
            return (null, (v, 0));
        }

        public override int Run(string[] remainingArguments) => Program.Run(Program.EnumerateInputFiles(m_input), NullifyFunction);

        private StringBuilder NullifyFunction(string file)
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
                    .Select(o => GetFunctionNode(o, m_functionName, m_keyword))
                    .Where(f => f != null))
                .FirstOrDefault();

            if (node == null)
            {
                return null;
            }

            var count = 0;
            var sb = new StringBuilder(text);

            switch (node)
            {
            case BaseMethodDeclarationSyntax m:
                count += NullifyFileCmd.NullifyFunction(m, sb);
                break;
            case AccessorDeclarationSyntax a:
                count += NullifyFileCmd.NullifyFunction(a, sb);
                break;
            case PropertyDeclarationSyntax p:
                count += NullifyFileCmd.OverwriteExpression(p.ExpressionBody, sb);
                break;
            }

            return count == 0 ? null : sb;
        }

        public static SyntaxNode GetFunctionNode(SyntaxNode node, (string Name, uint Crc32) functionName, string keyword, bool all = false)
        {
            switch (node)
            {
            case BaseMethodDeclarationSyntax m:
                return 
                    keyword == null &&
                    m.IsFunction(functionName) && 
                    (all || m.Body.HasStatements() || m.ExpressionBody?.Expression.HasCode() == true) ? m : null;
            case PropertyDeclarationSyntax p:
                if (p.Identifier.Text != functionName.Name)
                {
                    return null;
                }
                if (p.AccessorList == null)
                {
                    return keyword == null && (all || p.ExpressionBody?.Expression.HasCode() == true) ? p : null;
                }

                return p
                    .AccessorList
                    .Accessors
                    .FirstOrDefault(a => 
                        a.Keyword.Text == keyword &&
                        (all || a.Body.HasStatements() || a.ExpressionBody?.Expression.HasCode() == true));
            }
            return null;
        }
    }
}