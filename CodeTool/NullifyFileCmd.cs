using ManyConsole;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeTool
{
    class NullifyFileCmd : ConsoleCommand
    {
        private string m_input;

        public NullifyFileCmd()
        {
            IsCommand("nullify-file", "Nullifies the C# code in file by replacing method bodies with a throw statement.");

            HasRequiredOption("i=", "The input file or folder.", v => m_input = v);
        }

        public override int Run(string[] remainingArguments) => Program.Run(Program.EnumerateInputFiles(m_input), NullifyFile);

        private static StringBuilder NullifyFile(string file)
        {
            var count = 0;
            var text = File.ReadAllText(file);
            var sb = new StringBuilder(text);
            var tree = CSharpSyntaxTree.ParseText(text);
            var syntaxRoot = tree.GetRoot();
            foreach (var node in syntaxRoot.DescendantNodes().OrderByDescending(o => o.Span.End))
            {
                switch (node)
                {
                case BaseMethodDeclarationSyntax m:
                    count += NullifyFunction(m, sb);
                    break;
                case PropertyDeclarationSyntax p:
                    if (p.AccessorList != null)
                    {
                        foreach (var a in p.AccessorList.Accessors.OrderByDescending(o => o.Span.End))
                        {
                            count += NullifyFunction(a, sb);
                        }
                    }
                    else
                    {
                        count += OverwriteExpression(p.ExpressionBody, sb);
                    }
                    break;
                }
            }
            return count == 0 ? null : sb;
        }

        public static int NullifyFunction(AccessorDeclarationSyntax a, StringBuilder sb)
        {
            return a.Body == null
                ? OverwriteExpression(a.ExpressionBody, sb)
                : OverwriteBody(a.Body, sb);
        }

        public static int NullifyFunction(BaseMethodDeclarationSyntax m, StringBuilder sb)
        {
            int count = m.Body == null
                ? OverwriteExpression(m.ExpressionBody, sb)
                : OverwriteBody(m.Body, sb);

            {
                var asyncModifier = m.Modifiers.FirstOrDefault(o => o.Text == "async");
                if (asyncModifier.Text == "async")
                {
                    sb.Remove(asyncModifier.Span.Start, asyncModifier.Span.Length);
                    ++count;
                }
            }

            return count;
        }

        public static int OverwriteExpression(ArrowExpressionClauseSyntax exprBody, StringBuilder sb)
        {
            var expr = exprBody?.Expression;
            if (expr.HasCode())
            {
                sb.Remove(expr.Span.Start, expr.Span.Length);
                sb.Insert(expr.Span.Start, "throw new System.NotImplementedException()");
                return 1;
            }

            return 0;
        }

        public static int OverwriteBody(BlockSyntax body, StringBuilder sb)
        {
            if (body.HasStatements())
            {
                sb.Remove(body.Span.Start, body.Span.Length);
                sb.Insert(body.Span.Start, " => throw new System.NotImplementedException();");
                return 1;
            }

            return 0;
        }
    }
}