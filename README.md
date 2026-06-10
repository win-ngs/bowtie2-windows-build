## Bowtie 2 for Windows: Community-built Windows binaries

This repository provides a Bowtie 2 build that runs natively on Windows.
The release archive includes pre-compiled Bowtie 2 binaries and Windows
wrapper commands that users can run without building from source.

This is **not an official Bowtie 2 release**.
Official Bowtie 2 repository: https://github.com/BenLangmead/bowtie2

This build is based on upstream Bowtie 2 2.5.5.

These Windows executables were built using 
[MSYS2 UCRT64](https://www.msys2.org/docs/environments/).

## Downloading Bowtie 2 for Windows

Prebuilt Windows binaries are published on the
[Releases](https://github.com/win-ngs/bowtie2-windows-build/releases) page
of this repository.

Portable ZIP package:

```text
bowtie2-2.5.5-windows-ucrt64.zip
```

After extracting the portable ZIP archive, keep the files in the same folder.
The folder name does not matter. The important point is that the `.cmd`,
`.ps1`, and `.exe` files stay together:

```text
bowtie2.cmd
bowtie2-build.cmd
bowtie2-inspect.cmd
bowtie2.ps1
bowtie2-build.ps1
bowtie2-inspect.ps1
bowtie2-align-s.exe
bowtie2-align-l.exe
bowtie2-build-s.exe
bowtie2-build-l.exe
bowtie2-inspect-s.exe
bowtie2-inspect-l.exe
README.md
LICENSE.md
THIRD_PARTY_NOTICES.txt
LICENSES/
```

The wrapper/launcher scripts were re-written as PowerShell scripts (the included ".ps1" and ".cmd" files), obviating the need for Perl and Python to execute Bowtie 2.

## Running Bowtie 2 from PowerShell

Bowtie 2 is a command-line program. Open PowerShell, move into the extracted
folder, and run the commands as follows.

Check versions:

```powershell
.\bowtie2-build --version
.\bowtie2 --version
.\bowtie2-inspect --version
```

Build an index, inspect it, and align reads:

```powershell
# Build a small index.
.\bowtie2-build .\reference.fa .\index\ref

# Inspect the index.
.\bowtie2-inspect .\index\ref

# Align single-end reads and write SAM output.
.\bowtie2 -x .\index\ref -U .\reads.fastq -S .\aligned.sam
```

Write SAM output to stdout by omitting `-S`:

```powershell
.\bowtie2 -x .\index\ref -U .\reads.fastq
```

Do not use `-S -`. Bowtie 2 treats it as a literal output filename named `-`.

For large indexes, pass `--large-index`:

```powershell
.\bowtie2-build --large-index .\large_reference.fa .\index\large_ref
.\bowtie2 --large-index -x .\index\large_ref -U .\reads.fastq -S .\aligned.sam
.\bowtie2-inspect --large-index .\index\large_ref
```

If `--large-index` is not specified, the wrappers automatically use the large
executable when a large index exists and the corresponding small index does not.

For detailed usage and option descriptions, refer to the
official Bowtie 2 documentation:

https://bowtie-bio.sourceforge.net/bowtie2/manual.shtml


## Limitations

Use the `.cmd` commands for normal Windows use. They are native Windows wrapper
commands and do not require Perl or Python.

The PowerShell `bowtie2.ps1` wrapper intentionally does not implement upstream
Perl-wrapper paths that require shell pipelines or external helper tools:

- `--un*`
- `--al*`
- `--bam`

Use direct SAM output options, or run additional filtering/conversion tools
outside Bowtie 2.

Zstandard support is not enabled in this build; see
[zstd support note](#zstd-support-note). GZIP is supported.


## Validation performed

The Windows wrappers and patched binaries were checked with Windows PowerShell
5.1 and MSYS2-UCRT64-built executables.

The following checks were run:

```text
bowtie2-build.cmd --version
bowtie2.cmd --version
bowtie2-inspect.cmd --version
bowtie2-build.cmd example/reference/lambda_virus.fa <index>
bowtie2-inspect.cmd <index>
bowtie2.cmd -x <index> -U example/reads/longreads.fq -u 5 -S out.sam
bowtie2.cmd -x <index> -U example/reads/longreads.fq -u 5
```

Observed alignment result:

```text
5 reads; of these:
  5 (100.00%) were unpaired; of these:
    0 (0.00%) aligned 0 times
    5 (100.00%) aligned exactly 1 time
    0 (0.00%) aligned >1 times
100.00% overall alignment rate
```

Line ending checks:

```text
-S out.sam     -> LF=8, CRLF=0, BareLF=8
stdout SAM     -> LF=8, CRLF=0, BareLF=8
CRLF FASTQ     -> alignment succeeded
```

The distribution layout was also tested by placing the `.cmd`, `.ps1`, and
`.exe` files in the same temporary folder. The folder path and index path used
spaces, and `bowtie2-build.cmd`, `bowtie2-inspect.cmd`, and `bowtie2.cmd` all
completed successfully.



## Build from source

You do not need to build Bowtie 2 yourself if you only want to use the released
Windows binaries. This section is for maintainers or users who want to recreate
the build.

Install [MSYS2](https://www.msys2.org/) first. Open the **MSYS2 UCRT64**
terminal and install the required build packages:

```bash
pacman -S --needed base-devel mingw-w64-ucrt-x86_64-toolchain
```

The UCRT64 toolchain group includes `mingw-w64-ucrt-x86_64-gcc`. In the tested
MSYS2 package set, `mingw-w64-ucrt-x86_64-zlib` is installed as a dependency of
the toolchain packages.

Move into the source directory:

```bash
cd /c/Users/shu/dev/win-ngs/bowtie2-windows-build/bowtie2-2.5.5-80e1011-patch
```

Build:

```bash
make -j4 all \
  MINGW=1 \
  WINDOWS=1 \
  CXX=g++ \
  CC=gcc \
  AR=ar \
  RC=windres \
  LD=ld \
  STRIP=strip
```

For a machine with more cores, increase `-j4`, for example `-j8`.

Expected executable names:

```text
bowtie2-align-l.exe
bowtie2-align-s.exe
bowtie2-build-l.exe
bowtie2-build-s.exe
bowtie2-inspect-l.exe
bowtie2-inspect-s.exe
```

Check the build options:

```bash
./bowtie2-align-s.exe --version
```

The `Options:` line should include:

```text
-DPOPCNT_CAPABILITY -DNO_SPINLOCK -DWITH_QUEUELOCK=1 -static-libgcc -static-libstdc++ -static
```

It should not include:

```text
-DWITH_ZSTD
```

Release executables are stripped with `strip --strip-all` before packaging.

## MSYS2-UCRT64 build notes

The upstream Bowtie 2 `Makefile` tries to detect MinGW with this kind of check:

```make
ifneq (,$(findstring mingw,$(shell $(CXX) --version)))
  WINDOWS := 1
  MINGW := 1
endif
```

MSYS2 UCRT64 GCC reports a target of `x86_64-w64-mingw32`, but the first line of
`g++ --version` may not contain the lowercase string `mingw`. In that case the
automatic Makefile detection does not enter the Windows branch.

Passing `MINGW=1 WINDOWS=1` avoids that problem and enables the Windows-specific
settings:

- no Bowtie memory-mapped file support on Windows
- no Bowtie shared-memory support on Windows
- no AVX2 variant in this Windows build path
- Windows `.bat` wrapper generation
- `-static-libgcc -static-libstdc++ -static` in `CXXFLAGS`

The tool variables are also explicit because the Makefile's MinGW branch sets
cross-compiler names such as `x86_64-w64-mingw32-g++-posix`. Those names are not
the right tools for the UCRT64 terminal. Using `g++` and `gcc` keeps the build on
the active UCRT64 compiler.

With current MSYS2 GCC, the build may print warnings similar to:

```text
warning: template-id not allowed for constructor in C++20
warning: 'regs.regs_t::ECX' may be used uninitialized
warning: unused variable 'riter'
```

These warnings did not prevent the tested build from completing.

## Windows PowerShell wrappers

This Windows build does not use the upstream wrapper scripts directly for normal
Windows use. The upstream `bowtie2` wrapper is a Perl script, and the upstream
`bowtie2-build` and `bowtie2-inspect` launchers are Python scripts. The Perl
wrapper also contains Unix-oriented behavior such as shell pipelines, `mkfifo`,
`fork`, and PATH parsing with `:`.

This repository therefore provides native Windows wrapper scripts:

```text
bowtie2.ps1
bowtie2-build.ps1
bowtie2-inspect.ps1
```

These PowerShell scripts choose the correct compiled executable and pass the
arguments to it:

```text
bowtie2.ps1         -> bowtie2-align-s.exe or bowtie2-align-l.exe
bowtie2-build.ps1   -> bowtie2-build-s.exe or bowtie2-build-l.exe
bowtie2-inspect.ps1 -> bowtie2-inspect-s.exe or bowtie2-inspect-l.exe
```

They are written for Windows PowerShell 5.1, which is included with Windows.
They do not require PowerShell 7 (`pwsh.exe`). The scripts also avoid shell
command strings and forward `bowtie2` stdout as a byte stream so SAM output
keeps LF line endings.

For convenience, the release also includes `.cmd` launchers:

```text
bowtie2.cmd
bowtie2-build.cmd
bowtie2-inspect.cmd
```

Most users should run the `.cmd` commands. The `.cmd` files call the matching
`.ps1` script through `powershell.exe`.

## Developer notes for the Windows wrapper files

The `.cmd` files are small launchers. For example, `bowtie2.cmd` runs:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bowtie2.ps1" %*
```

The `.ps1` files then start the matching native executable:

```text
bowtie2.ps1         -> bowtie2-align-s.exe or bowtie2-align-l.exe
bowtie2-build.ps1   -> bowtie2-build-s.exe or bowtie2-build-l.exe
bowtie2-inspect.ps1 -> bowtie2-inspect-s.exe or bowtie2-inspect-l.exe
```

The `.ps1` wrappers first look for the required `.exe` in the same directory as
the wrapper. This supports the release archive layout where `.cmd`, `.ps1`, and
`.exe` files are kept together. If the `.exe` is not present in the same
directory, the wrappers fall back to `bowtie2-2.5.5-80e1011-patch/` for this
development workspace.

The `.ps1` wrappers use `.NET` `ProcessStartInfo` and explicit Windows argument
quoting. They do not use `system()`, `mkfifo`, `fork`, shell pipelines, or
colon-based PATH splitting. `bowtie2.ps1` forwards stdout as a byte stream so
streamed SAM output keeps LF line endings on native Windows.

## MSYS2-UCRT64 compatibility patch

The upstream Bowtie 2 2.5.5 source can be built in MSYS2-UCRT64, but native
Windows output streams default to text mode. Text mode translates every `\n`
written by the program into `\r\n`, which makes SAM output CRLF even though the
Bowtie 2 SAM writer appends LF internally.

The compatibility patch keeps buffered Bowtie 2 output LF-only on Windows.
Paths below are relative to the patched source directory
`bowtie2-2.5.5-80e1011-patch/`.

| File | Change | Reason |
|---|---|---|
| `filebuf.h` | Added Windows-only `<fcntl.h>` and `<io.h>` includes | Provides `O_BINARY`, `setmode()`, and `fileno()` for native Windows binary-mode output control |
| `filebuf.h` | Added `outFileMode(bool binary)`, which returns `"wb"` on Windows and preserves the previous `binary ? "wb" : "w"` behavior on non-Windows platforms | Prevents the Windows C runtime from translating LF to CRLF for `OutFileBuf` file outputs while leaving POSIX behavior unchanged |
| `filebuf.h` | Added `setStdoutBinaryMode()` and calls it from the default `OutFileBuf()` constructor | Keeps the default SAM output path, stdout, LF-only on native Windows |
| `filebuf.h` | Changed all `OutFileBuf` file-opening paths to call `outFileMode(binary)` instead of directly choosing `"w"` for text mode | Routes `-S <sam>` file output and other `OutFileBuf` file outputs through the same Windows LF-only handling |
| `../bowtie2.ps1` | Added a Windows PowerShell 5.1-compatible wrapper for `bowtie2-align-s.exe` / `bowtie2-align-l.exe` using `ProcessStartInfo`, explicit Windows argument quoting, byte-stream stdout forwarding, and same-folder-first executable lookup | Replaces the upstream Perl wrapper for normal Windows use without `system()`, shell pipelines, `mkfifo`, `fork`, or colon-based PATH parsing; also supports release ZIPs where exe/ps1/cmd files are in one folder |
| `../bowtie2-build.ps1` | Added a Windows PowerShell 5.1-compatible wrapper for `bowtie2-build-s.exe` / `bowtie2-build-l.exe` with small/large index selection, multi-FASTA argument normalization, and same-folder-first executable lookup | Replaces the upstream Python launcher so `python3` is not required for Windows builds; also supports release ZIPs where exe/ps1/cmd files are in one folder |
| `../bowtie2-inspect.ps1` | Added a Windows PowerShell 5.1-compatible wrapper for `bowtie2-inspect-s.exe` / `bowtie2-inspect-l.exe` with automatic large-index selection and same-folder-first executable lookup | Replaces the upstream Python launcher so `python3` is not required for Windows inspection; also supports release ZIPs where exe/ps1/cmd files are in one folder |
| `../bowtie2.cmd`, `../bowtie2-build.cmd`, `../bowtie2-inspect.cmd` | Added thin `cmd.exe` launchers that call `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` for the matching `.ps1` wrapper | Lets users run `bowtie2.cmd`-style commands on a stock Windows installation with Windows PowerShell 5.1 |

The modified source locations include comments explaining why binary mode is
forced for Windows output.

## zstd support note

The upstream Bowtie 2 manual does not say to pass `WITH_ZSTD=1` directly for a
normal build.

The manual says that:

```text
make static-libs && make STATIC_BUILD=1
```

will download zstd and zlib, compile them as static libraries, and link them
into Bowtie 2. In the upstream Makefile, `STATIC_BUILD` also enables zstd.

This UCRT64 build does not use that recipe. It uses the MSYS2 UCRT64 zlib
package and the regular dynamic `-lz` link path instead.

In local testing, explicitly enabling zstd with `WITH_ZSTD=1` produced binaries,
but direct alignment of the included uncompressed FASTQ failed with messages
like:

```text
is_zstd_file: unable to read magic number
Error: reads file does not look like a FASTQ file
```

The failure is in the read-file compression probing path for this Windows/UCRT64
build. The practical release build therefore omits `WITH_ZSTD=1`.

Gzip support remains linked through zlib (`-lz`).

## Cleaning

Clean generated Bowtie 2 build outputs from the source directory:

```bash
cd /c/Users/shu/dev/win-ngs/bowtie2-windows-build/bowtie2-2.5.5-80e1011-patch
make clean
```

This removes Bowtie 2 executables, generated `.bat` files, package zip files,
and the Makefile `.tmp` directory.

## License

Bowtie 2 is distributed under the GNU General Public License v3.

The root license file is included as:

```text
LICENSE
```

The release archive includes the same text as:

```text
LICENSE.md
```

Third-party and bundled-component notices are included in:

```text
THIRD_PARTY_NOTICES.txt
LICENSES/
```

## Disclaimer

This is a community/local Windows build recipe.

It is not provided, reviewed, or endorsed by the official Bowtie 2 developers.
Validate the binaries and alignment results in your own analysis environment
before using them in production workflows.
