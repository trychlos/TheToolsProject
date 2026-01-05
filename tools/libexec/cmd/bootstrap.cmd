@echo off
	rem TheToolsProject - Tools System and Working Paradigm for IT Production
	rem Copyright (C) 1998-2023 Pierre Wieser (see AUTHORS)
	rem Copyright (C) 2023-2026 PWI Consulting
	rem
	rem TheToolsProject is free software; you can redistribute it and/or
	rem modify it under the terms of the GNU General Public License as
	rem published by the Free Software Foundation; either version 2 of the
	rem License, or (at your option) any later version.
	rem
	rem TheToolsProject is distributed in the hope that it will be useful,
	rem but WITHOUT ANY WARRANTY; without even the implied warranty of
	rem MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
	rem General Public License for more details.
	rem
	rem You should have received a copy of the GNU General Public License
	rem along with TheToolsProject; see the file COPYING. If not,
	rem see <http://www.gnu.org/licenses/>.
	rem
	rem TTP boostrapping in a cmd environment

	setlocal EnableDelayedExpansion

	REM Default config directories
	set "default_dirs=C:\ProgramData\ttp.d %USERPROFILE%\.ttp.d"

	REM Allow override via command-line
	if "%~1"=="" (
		set "config_dirs=%default_dirs%"
	) else (
		set "config_dirs=%*"
	)

	REM Reset variables
	set "TTP_ROOTS="
	set "prepend_roots="
	set "append_roots="

	REM Load .conf files from specified directories
	for %%D in (%config_dirs%) do (
		for %%F in ("%%D\*.conf") do (
			if exist "%%F" (
				for /f "usebackq tokens=* delims=" %%L in ("%%F") do (
					set "line=%%L"
					REM Skip comments and empty lines
					if not "!line!"=="" if "!line:~0,1!" NEQ "#" (
						REM Handle lines starting with '-'
						if "!line:~0,1!"=="-" (
							set "line=!line:~1!"
							if defined prepend_roots (
								set "prepend_roots=!prepend_roots!;!line!"
							) else (
								set "prepend_roots=!line!"
							)
						) else (
							if defined append_roots (
								set "append_roots=!append_roots!;!line!"
							) else (
								set "append_roots=!line!"
							)
						)
					)
				)
			)
		)
	)

	REM Build TTP_ROOTS: prepend_roots ; append_roots
	if defined prepend_roots (
		if defined append_roots (
			set "TTP_ROOTS=!prepend_roots!;!append_roots!"
		) else (
			set "TTP_ROOTS=!prepend_roots!"
		)
	) else (
		set "TTP_ROOTS=!append_roots!"
	)

	REM update PATH from TTP_ROOTS
	rem during development, may happen to have an empty path (oop's) so have at least the minimum required (make sure we have reg.exe)
	set "PATH=%PATH%;%SystemRoot%\system32"
	for /F "tokens=2,*" %%T in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v PATH') do call set "PATH=%%~U"
	rem @echo before PATH=%PATH%
	for %%D in (%TTP_ROOTS:;= %) do (
		call :addPart PATH %%D\bin
	)
	rem @echo after PATH=%PATH%

	REM Update PERL5LIB from TTP_ROOTS
	set PERL5LIB=
	for /F "tokens=2,*" %%T in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v PERL5LIB 2^>nul') do call set "PERL5LIB=%%~U"
	rem @echo before PERL5LIB=%PERL5LIB%
	for %%D in (%TTP_ROOTS:;= %) do (
		call :addPart PERL5LIB %%D\libexec\perl
		if defined PERL5LIB (
			call :addPart PERL5LIB %%D\libexec\perl
		) else (
			set "PERL5LIB=%%D\libexec\perl"
		)
	)
	rem @echo after PERL5LIB=%PERL5LIB%

	REM Set TTP_NODE if not defined
	if not defined TTP_NODE (
		set "TTP_NODE=%COMPUTERNAME%"
	)

	rem logs
	rem @echo " "  >>C:\TEMP\bootstrap.log
	rem @echo %DATE% %TIME%  >>C:\TEMP\bootstrap.log
	rem @echo TTP_ROOTS: %TTP_ROOTS% >>C:\TEMP\bootstrap.log
	rem @echo PATH: %PATH% >>C:\TEMP\bootstrap.log
	rem @echo PERL5LIB : %PERL5LIB%  >>C:\TEMP\bootstrap.log
	rem @echo TTP_NODE : %TTP_NODE%  >>C:\TEMP\bootstrap.log

	endlocal & (
		call :setVar TTP_ROOTS "%TTP_ROOTS%"
		call :setVar TTP_NODE "%TTP_NODE%"
		call :setVar PERL5LIB "%PERL5LIB%"
		call :setVar PATH "%PATH%"
	)

	REM Force environment refresh so new CMD windows see updated vars
	rem NB: This is supposed to force-refresh the environment in some contexts.
	rem NB- But it often doesn't affect Explorer or existing processes reliably.
	RUNDLL32.EXE USER32.DLL,UpdatePerUserSystemParameters ,1 ,True

	rem ultimately restart explorer
	rem most probably an effect of laws of murphy: while killing the explorer works fine, re-starting it has often unwanted and unpredictable side effects
	rem e.g. not starting at all! so just give up with this option
	rem taskkill /f /im explorer.exe
	rem start explorer.exe

	exit /b

	rem add an element to a variable if not already exists
	rem this is a very simple function which just tries to match the exact provided part
	rem 1. variable name
	rem 2. part to add if not already exists
:addPart
	set name=%1
	rem @echo name=%name%
	rem @echo value=!%name%!
	set "value=!%name%!"
	set "part=%2"
	if not "!value!" == "!value:%part%=!" (
		rem echo %part% is already in all
	) else (
		set "%1=!value!;%2"
	)
	exit /b

	rem set an environment variable both in the current session and in the registry (user environment)
:setVar
	set "%1=%~2"
	reg add "HKCU\Environment" /v %1 /t REG_EXPAND_SZ /d "%~2" /f 1>nul
	exit /b
