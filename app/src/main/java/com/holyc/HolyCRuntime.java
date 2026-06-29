package com.holyc;

/** JNI bridge to the ARM64 HolyC compiler. */
public final class HolyCRuntime {
    static {
        System.loadLibrary("holyc");
    }

    private HolyCRuntime() {}

    /**
     * Lex, parse, generate ARM64 machine code and execute it in-process.
     * Returns the program output, or a human-readable error message.
     */
    public static native String compileAndRun(String source);
}
