package com.holyc;

/** Seed programs that exercise the real compiler (functions, loops, args). */
final class Examples {
    private Examples() {}

    static final String HELLO =
        "// HolyC, compiled to ARM64 machine code on your phone.\n" +
        "// Press RUN — this is a real JIT compiler, not a sandbox.\n" +
        "\n" +
        "I64 Add(I64 a, I64 b) {\n" +
        "  return a + b;\n" +
        "}\n" +
        "\n" +
        "U0 Main() {\n" +
        "  I64 x = Add(10, 32);\n" +
        "  \"Add(10, 32) = %d\\n\", x;\n" +
        "}\n" +
        "\n" +
        "Main;\n";

    static final String FACTORIAL =
        "// while-loops, multiple functions and printf-style output,\n" +
        "// all lowered to native ARM64 by the assembler backend.\n" +
        "\n" +
        "I64 Fact(I64 n) {\n" +
        "  I64 r = 1;\n" +
        "  I64 i = 1;\n" +
        "  while (i <= n) {\n" +
        "    r = r * i;\n" +
        "    i = i + 1;\n" +
        "  }\n" +
        "  return r;\n" +
        "}\n" +
        "\n" +
        "U0 Main() {\n" +
        "  I64 k = 1;\n" +
        "  while (k <= 10) {\n" +
        "    \"%d! = %d\\n\", k, Fact(k);\n" +
        "    k = k + 1;\n" +
        "  }\n" +
        "}\n" +
        "\n" +
        "Main;\n";
}
