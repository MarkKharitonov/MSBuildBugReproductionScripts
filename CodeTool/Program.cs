using Crc32C;
using ManyConsole;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Text;

namespace CodeTool
{
    public static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern int GetConsoleProcessList(int[] pids, int arraySize);

        private static bool OwnsConsole()
        {
            var pids = new int[1];   // Intentionally too short
            return GetConsoleProcessList(pids, pids.Length) == 1;
        }

        static int Main(string[] args)
        {
            try
            {
                var commands = ConsoleCommandDispatcher.FindCommandsInSameAssemblyAs(typeof(Program));
                foreach (var c in commands)
                {
                    c.SkipsCommandSummaryBeforeRunning();
                }
                return ConsoleCommandDispatcher.DispatchCommand(commands, args, Console.Out);
            }
            catch (Exception exc)
            {
                Console.Error.WriteLine(exc);
                return 100;
            }
            finally
            {
                if (!Console.IsOutputRedirected && OwnsConsole())
                {
                    Console.WriteLine("Press any key to exit ...");
                    Console.ReadKey();
                }
            }
        }

        public static bool HasCode(this ExpressionSyntax expr) => expr != null && (
                !(expr is ThrowExpressionSyntax throwExpr) ||
                throwExpr.ToString() != "throw new System.NotImplementedException()"
            );

        public static bool HasStatements(this BlockSyntax body) => body?.Statements.Count > 0;

        public static bool IsFunction(this BaseMethodDeclarationSyntax m, (string Name, uint Crc32) functionName) => functionName.Crc32 > 0
            ? m.FullName() == functionName
            : m.Identifier().Text == functionName.Name;

        public static (string, uint) FullName(this BaseMethodDeclarationSyntax m)
        {
            var types = string.Join(",",m.ParameterList.Parameters.Select(p => p.Type.ToFullString()));
            var crc32 = Crc32CAlgorithm.Compute(Encoding.UTF8.GetBytes(types));
            return (m.Identifier().Text, crc32);
        }

        public static SyntaxToken Identifier(this BaseMethodDeclarationSyntax o)
        {
            switch (o)
            {
            case MethodDeclarationSyntax m:
                return m.Identifier;
            case ConstructorDeclarationSyntax c:
                return c.Identifier;
            }
            throw new NotImplementedException();
        }

        public static IEnumerable<string> EnumerateInputFiles(string input)
        {
            if (Directory.Exists(input))
            {
                return Directory.EnumerateFiles(input, "*.cs", SearchOption.AllDirectories);
            }
            return new[] { input };
        }

        public static int Run(IEnumerable<string> files, Func<string, StringBuilder> action)
        {
            int count = 0;
            ExceptionDispatchInfo edi = null;
            foreach (var file in files)
            {
                try
                {
                    var sb = action(file);
                    if (sb != null)
                    {
                        File.WriteAllText(file, sb.ToString());
                        ++count;
                    }
                }
                catch (Exception exc)
                {
                    Console.Error.WriteLine(exc);
                    if (edi == null)
                    {
                        edi = ExceptionDispatchInfo.Capture(exc);
                    }
                }
            }

            edi?.Throw();

            Console.WriteLine(count);
            return 0;
        }
    }
}