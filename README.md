# HolyC IDE

Android IDE for the HolyC programming language — the language Terry Davis wrote for [TempleOS](https://en.wikipedia.org/wiki/TempleOS).

Write HolyC code, press **RUN**, and it compiles to native ARM64 machine code and executes on-device in milliseconds. No interpreter, no VM — real JIT compilation via `mmap(PROT_EXEC)`.

## Features

- **Real JIT compiler** — full HolyC compiler in C + ARM64 machine code generated at runtime
- **Code editor** with line numbers
- **File manager** — create, open, delete `.HC` files; open from system file manager
- **Zero dependencies** — pure Java UI, no Kotlin, no AndroidX, no third-party libraries
- **Tiny APK** — ~166 KB

## Supported HolyC

```c
// Integer types (all 64-bit)
I64 x = 42;  U64 u = 100;  CH c = 'A';  I8 b = -1;

// Type definitions
typedef struct { I64 x; I64 y; } Point;

// Control flow
if (x > 0) { ... } else { ... }
while (x > 0) { x--; }
for (I64 i = 0; i < 10; i++) { sum += i; }

// Operators: + - * / % ++ -- += -= *= /=
// Comparison: < > <= >= == !=  Logical: ! && ||

// Pointers
I64 *ptr = MAlloc(sizeof(I64));
*ptr = 999;

// Structs
Point p;  p.x = 10;  p.y = 20;
Point *pp = MAlloc(sizeof(Point));  pp->x = 30;

// Arrays
I64 arr[10];  arr[0] = 1;

// Functions
I64 Fib(I64 n) { if (n <= 1) return n; return Fib(n-1) + Fib(n-2); }

// Printf: %d %u %c %s %p
"Result: %d, char: %c\n", value, 65;

// Built-ins: MAlloc, Free, StrLen, StrCpy, StrCat, GetTSC
// Constants: PAGE_SIZE

// Entry point
Main;
```

## Build

Requirements: Android NDK 26, SDK 34, Gradle 8.4, JDK 21, AGP 8.3.

```sh
gradle assembleDebug --no-daemon
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Architecture

| File | Description |
|------|-------------|
| `compiler.c` | Full HolyC compiler: lexer + recursive-descent parser + ARM64 codegen |
| `runtime.S` | `mmap` JIT allocator, output buffer, print helpers, MAlloc/Free, string functions |
| `bridge.c` | JNI glue — runs the pipeline, returns output to Java |

## Requirements

- Android 7.0+ (API 24)
- arm64-v8a device (ARM64)
