@echo off
rem mayoi-java python-free jdtls launcher (replicates official jdtls.py semantics, no version check)
rem java resolution: managed JRE (%~dp0..\jre), then JAVA_HOME, then PATH; -data uses sanitized cwd basename
rem NOTE: official-style --jvm-arg= / --java-executable / -data overrides are NOT parsed here; all args are passed through verbatim to java
setlocal EnableExtensions DisableDelayedExpansion

set "HERE=%~dp0"
set "JRE_JAVA=%HERE%..\jre\bin\java.exe"
set "JAVA_EXE="

if exist "%JRE_JAVA%" set "JAVA_EXE=%JRE_JAVA%"
if not defined JAVA_EXE if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "NoDefaultCurrentDirectoryInExePath=1"
if not defined JAVA_EXE (
    for /f "delims=" %%p in ('where "$PATH:java" 2^>nul ^| findstr /i /v "WindowsApps"') do set "JAVA_EXE=%%p" & goto :java_found
)
:java_found
if not defined JAVA_EXE (
    echo mayoi-java: java not found. Re-run the bootstrap to install the managed JRE, or install JDK 21+. 1>&2
    exit /b 1
)

rem locate equinox launcher: exact name first, then versioned glob
set "JDTLS_DIR=%HERE%..\jdtls"
set "LAUNCHER="
if exist "%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar" set "LAUNCHER=%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar"
if not defined LAUNCHER (
    for /r "%JDTLS_DIR%\plugins" %%f in (org.eclipse.equinox.launcher_*.jar) do set "LAUNCHER=%%f" & goto :launcher_found
)
:launcher_found
if not defined LAUNCHER (
    echo mayoi-java: no equinox launcher found under "%JDTLS_DIR%". 1>&2
    exit /b 1
)

rem platform shared configuration
set "CONFIG_DIR=config_win"

rem -data dir: %APPDATA%\mayoi-java\jdtls\[sanitized cwd basename]
if not defined APPDATA set "APPDATA=%LOCALAPPDATA%"
for %%p in ("%CD%") do set "CWD_NAME=%%~nxp"
if not defined CWD_NAME set "CWD_NAME=_root_"
set "CWD_NAME=%CWD_NAME:\=_%"
set "CWD_NAME=%CWD_NAME:/=_%"
set "CWD_NAME=%CWD_NAME::=_%"
set "CWD_NAME=%CWD_NAME:?=_%"
set "CWD_NAME=%CWD_NAME:<=_%"
set "CWD_NAME=%CWD_NAME:>=_%"
set "CWD_NAME=%CWD_NAME:|=_%"
set "CWD_NAME=%CWD_NAME: =_%"
set "CWD_NAME=%CWD_NAME:~0,64%"
set "DATA_DIR=%APPDATA%\mayoi-java\jdtls\%CWD_NAME%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>nul
if not exist "%DATA_DIR%" (
    echo mayoi-java: cannot create data dir "%DATA_DIR%" 1>&2
    exit /b 1
)

"%JAVA_EXE%" ^
  -Declipse.application=org.eclipse.jdt.ls.core.id1 ^
  -Dosgi.bundles.defaultStartLevel=4 ^
  -Declipse.product=org.eclipse.jdt.ls.core.product ^
  -Dosgi.checkConfiguration=true ^
  "-Dosgi.sharedConfiguration.area=%JDTLS_DIR%\%CONFIG_DIR%" ^
  -Dosgi.sharedConfiguration.area.readOnly=true ^
  -Dosgi.configuration.cascaded=true ^
  -Xms1G ^
  --add-modules=ALL-SYSTEM ^
  --add-opens java.base/java.util=ALL-UNNAMED ^
  --add-opens java.base/java.lang=ALL-UNNAMED ^
  -Djdk.xml.maxGeneralEntitySizeLimit=0 ^
  -Djdk.xml.totalEntitySizeLimit=0 ^
  -jar "%LAUNCHER%" ^
  -data "%DATA_DIR%" %*
