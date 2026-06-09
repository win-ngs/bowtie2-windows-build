# Runtime DLL Notes

The tested Bowtie 2 Windows UCRT64 release does not package MSYS2 runtime DLLs.

The executables were built with:

```text
-static-libgcc -static-libstdc++ -static
```

`objdump -p` on the Bowtie 2 executables showed imports from Windows
system/UCRT API-set DLLs, for example:

```text
KERNEL32.dll
api-ms-win-crt-runtime-l1-1-0.dll
api-ms-win-crt-stdio-l1-1-0.dll
api-ms-win-crt-string-l1-1-0.dll
```

No `libgcc_s`, `libstdc++`, `libwinpthread`, `zlib1`, or MSYS2 runtime DLL is
included in this release folder.

License texts for statically linked or build-time third-party components are
kept in sibling directories:

```text
LICENSES/bowtie2/
LICENSES/zlib/
LICENSES/gcc-libs/
```
