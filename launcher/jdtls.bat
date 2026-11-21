@echo off
rem mayoi-java 免 Python jdtls 启动器（复刻官方 jdtls.py 启动语义，无版本校验）
rem java 解析：受管 JRE（%~dp0..\jre）> JAVA_HOME > PATH；-data 用净化 cwd 目录名
setlocal EnableExtensions

set "HERE=%~dp0"
set "JRE_JAVA=%HERE%..\jre\bin\java.exe"
set "JAVA_EXE="

if exist "%JRE_JAVA%" set "JAVA_EXE=%JRE_JAVA%"
if not defined JAVA_EXE if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
if not defined JAVA_EXE (
    where java >nul 2>nul && set "JAVA_EXE=java"
)
if not defined JAVA_EXE (
    echo mayoi-java: 未找到 java。请重跑引导脚本安装受管 JRE，或安装 JDK 21+。 1>&2
    exit /b 1
)

rem 定位 equinox launcher：优先精确名，再 glob 版本名
set "JDTLS_DIR=%HERE%..\jdtls"
set "LAUNCHER="
if exist "%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar" set "LAUNCHER=%JDTLS_DIR%\plugins\org.eclipse.equinox.launcher.jar"
if not defined LAUNCHER (
    for /r "%JDTLS_DIR%\plugins" %%f in (org.eclipse.equinox.launcher_*.jar) do set "LAUNCHER=%%f" & goto :launcher_found
)
:launcher_found
if not defined LAUNCHER (
    echo mayoi-java: 在 %JDTLS_DIR% 下未找到 equinox launcher。 1>&2
    exit /b 1
)

rem 平台 shared configuration
set "CONFIG_DIR=config_win"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "CONFIG_DIR=config_win"

rem -data 目录：%APPDATA%\mayoi-java\jdtls\<净化 cwd 目录名>
set "CWD_NAME=%CD%"
for %%p in ("%CD%") do set "CWD_NAME=%%~nxp"
set "CWD_NAME=%CWD_NAME:\=_%"
set "CWD_NAME=%CWD_NAME:/=_%"
set "CWD_NAME=%CWD_NAME::=_%"
set "CWD_NAME=%CWD_NAME:?=_%"
set "CWD_NAME=%CWD_NAME:<=_%"
set "CWD_NAME=%CWD_NAME:>=_%"
set "CWD_NAME=%CWD_NAME:|=_%"
set "CWD_NAME=%CWD_NAME: =_%"
set "DATA_DIR=%APPDATA%\mayoi-java\jdtls\%CWD_NAME%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>nul

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
