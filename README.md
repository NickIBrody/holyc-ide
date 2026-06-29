# HolyC IDE

Android IDE for the HolyC programming language — the language Terry Davis wrote for [TempleOS](https://en.wikipedia.org/wiki/TempleOS).

Write HolyC code, press **RUN**, and it compiles to native ARM64 machine code and executes on-device in milliseconds. No interpreter, no VM — real JIT compilation via `mmap(PROT_EXEC)`.

## Features

- **Real JIT compiler** — lexer → parser → codegen → runtime, all in ARM64 assembly (~2500 lines of `.S`)
- **Code editor** with line numbers
- **File manager** — create, open, delete `.HC` files
- **Zero dependencies** — pure Java UI, no Kotlin, no AndroidX, no third-party libraries
- **Tiny APK** — ~62 KB

## Supported HolyC subset

```c
// Types
I64  x = 42;
U0   Main() { ... }

// Control flow
if (x > 0) { ... } else { ... }
while (x > 0) { x = x - 1; }

// Functions
I64 Add(I64 a, I64 b) { return a + b; }

// Print
"Result: %d\n", value;

// Entry point
Main;
```

## Build

Requirements: Android NDK 26, SDK 34, Gradle 8.4, JDK 21, AGP 8.3.

```sh
cd holyc-ide
gradle assembleDebug --no-daemon
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Architecture

| File | Description |
|------|-------------|
| `lexer.S` | Tokenizer — integers, identifiers, 6 keywords, strings, operators |
| `parser.S` | Recursive-descent parser → arena-allocated AST |
| `codegen.S` | ARM64 machine code generator with local variable table and branch patching |
| `runtime.S` | `mmap` JIT allocator, output buffer, `hc_run` dispatcher |
| `bridge.c` | JNI glue — calls the pipeline, returns output string to Java |

## Requirements

- Android 7.0+ (API 24)
- arm64-v8a device (ARM64)
