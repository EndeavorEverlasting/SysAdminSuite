# Native mapping tools (no CLR)

`SysAdminSuite.Mapping.Worker.exe` and `SysAdminSuite.Mapping.Controller.exe` replace the PowerShell worker/controller path for environments that block `powershell.exe` on endpoints. Behavior and artifacts are described in [CONTRACT.md](CONTRACT.md).

## Build (Windows)

Requirements: **Visual Studio 2022** (or Build Tools) with **Desktop development with C++**, and **CMake** 3.20+ on `PATH`.

```bat
cd mapping\native
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

Run unit tests (GoogleTest):

```bat
ctest --test-dir build -C Release --output-on-failure
```

Outputs (default): `build\bin\Release\SysAdminSuite.Mapping.Worker.exe` and `SysAdminSuite.Mapping.Controller.exe`. Keep both binaries in the **same directory** so the controller can find the worker by default (`-LocalWorkerPath` overrides).

CI builds the same layout on `windows-latest` (see `.github/workflows/native-build.yml`).

## Signing (release)

Enterprise policies often require **Authenticode** signatures on both executables. Sign after the Release build with your org’s certificate (thumbprint in secure storage or HSM), then distribute the signed pair together.

## Quick test (local machine)

Worker (inventory only; writes under ProgramData):

```bat
build\bin\Release\SysAdminSuite.Mapping.Worker.exe -ListOnly -Preflight -OutputRoot "%TEMP%\SAS-Map-Test"
```

Controller (remote hosts; requires admin share access and rights to create scheduled tasks):

```bat
build\bin\Release\SysAdminSuite.Mapping.Controller.exe -Computer localhost -WorkerArgs "-ListOnly -Preflight -OutputRoot C:\ProgramData\SysAdminSuite\Mapping"
```

Use real hostnames instead of `localhost` for remote scenarios; the controller stages the worker over `\\HOST\C$`.
