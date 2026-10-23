# Maintained fork

Repository: https://github.com/allenyllee/PlexServerAutoUpdater

Upstream: https://github.com/TechieGuy12/PlexServerAutoUpdater

Maintenance branch: `codex/reliable-windows-updates`.

This fork keeps the original Windows Forms application, .NET Framework 4.8,
service-account discovery, public/Plex Pass channels, and `-silent`, `-wait`,
`-force`, and `-log` parameters. It replaces neither PlexService nor its tray UI.

## Problems and fixes

- Upstream issue #67 reports a newer platform version paired with the old x86
  installer, and PlexService remaining stopped after process termination fails.
- Upstream issue #63 reports incorrect architecture detection for custom paths.
- Upstream PR #68 by joshuabrosenthal repairs shutdown/recovery exception paths.
  Its original commit is retained in this branch. This fork extracts the update
  sequence into a tested helper; restart is attempted even when stopping,
  process cleanup, or installation fails. Multiple failures remain visible.
- Detect x86/x64 from the actual installed executable's PE machine field.
  Prefer the standard x64 path over obsolete x86 remnants; retain explicit
  `PlexInstallLocation` for custom installations.
- Derive the update version and cache directory from the selected architecture's
  installer URL, rather than the platform-level version. Reject mismatched
  filenames and unsupported executable architectures.
- Enable TLS 1.2, reject unsuccessful HTTP responses, fix null checksum handling,
  and report installer exit codes and post-install version mismatches.
- Query DVR presence before scheduled recordings: servers without a DVR can
  return 401 for the latter endpoint. Unknown playback/recording status prevents
  an update. Silent mode waits synchronously for idle instead of exiting with a
  background timer. `-force` still cannot interrupt recording.
- Treat `-log` as a directory, as documented; fix the default installer log path.
- Use `/SUPPRESSMSGBOXES /SP-` and `/LOG="path"` for x64 Inno Setup. A live
  scheduled update exposed a migration message for an old x86 installation,
  which otherwise blocks unattended installation despite `/verysilent`.
- `-check -silent` checks/downloads the matching package without stopping the
  service or installing it. This mode does not require elevation.

## Build and verify

Run in Windows PowerShell 5.1 on Windows with .NET Framework 4.8:

```powershell
.\build.ps1 -Test
.\bin\Release\psupdate.exe -check -silent -log C:\PlexUpdaterLogs
```

The build restores pinned Roslyn, .NET 4.8 reference assemblies, and Newtonsoft
Json packages from NuGet. Output is `bin/Release`. The regression executable
tests PE parsing, per-architecture versions/cache folders, and update recovery
without modifying Windows services. GitHub Actions runs the same build/tests.

Deploy `psupdate.exe`, `psupdate.exe.config`, and `Newtonsoft.Json.dll` together.
Preserve the local service name, installation path, and data-directory settings.
Schedule `psupdate.exe -silent -log <directory>` as the service account with
highest privileges. Never put the account password or Plex token in Git.

## Validation record

2026-10-23: Windows build succeeded; 37 regression assertions passed. Live
`-check -silent` returned 0 and correctly selected the x64 release, rejected an
incomplete cached installer, downloaded it again, and verified the checksum.
See local deployment notes for the installed commit and live upgrade outcome.

Upstream references:
- https://github.com/TechieGuy12/PlexServerAutoUpdater/issues/67
- https://github.com/TechieGuy12/PlexServerAutoUpdater/issues/63
- https://github.com/TechieGuy12/PlexServerAutoUpdater/pull/68

Limitations: the original architecture is Windows x86/x64 only. Package integrity
uses the upstream SHA-1 checksum over HTTPS; this is not an independent publisher
signature check. A failed service restart is reported, not guaranteed recoverable.
