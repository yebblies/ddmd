
Overview:
--------------------

This project is a port of the [DMD frontend](https://github.com/D-Programming-Language/dmd), automatically translated from C++ to D using [magicport2](https://github.com/yebblies/magicport2).  The current version is based on dmd 2.067.

This project is designed to be built with dub. ([dub package](http://code.dlang.org/packages/ddmd))

Currently only the lexer and some support modules are included.

This project may eventually be merged into dmd upstream development.  No stable API is provided.

As the code is automatically generated, pull requests should be made against [upstream](https://github.com/D-Programming-Language/dmd).

Warnings and deprecations currently need to be disabled for the code to compile successfully.

Example:
--------------------

```json
{
    "name": "ddmdlexertest",
    "dependencies": {
        "ddmd": ">=0.0.7"
    }
}
```

```d
import std.stdio;
import std.file;

import ddmd.tokens;
import ddmd.lexer;

/////////////////////////

void main()
{
    string data = "void blah() {} // stuff";
    auto l = new Lexer("myfile", data.ptr, 0, data.length, 0, 0);
    l.nextToken();
    do
    {
        printf("token: %s\n", l.token.toChars());
    }
    while (l.nextToken() != TOKeof);
}
```
