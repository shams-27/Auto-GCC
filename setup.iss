[Setup]
AppName=Auto GCC Installer
AppVersion=2.0
DefaultDirName={tmp}\shams_gcc
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=
Compression=lzma
DisableDirPage=yes
DisableProgramGroupPage=yes
Uninstallable=no
OutputBaseFilename=shams_gcc_setup

[Files]
Source: "shams_gcc.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Run]
Filename: "{tmp}\shams_gcc.exe"; Flags: waituntilterminated
