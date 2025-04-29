@echo off
	rem TheToolsProject - Tools System and Working Paradigm for IT Production
	rem Copyright (C) 1998-2023 Pierre Wieser (see AUTHORS)
	rem Copyright (C) 2023-2025 PWI Consulting
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

	shift & goto :%~1

	rem header and footer of each test directory
:color_blue
	powershell write-host -foreground Cyan %~1
	exit /b

	rem add-on messages for an individual test
:color_cyan
	powershell write-host -foreground DarkCyan %~1
	exit /b

	rem error messages
:color_red
	powershell write-host -foreground Red %~1
	exit /b

	rem count lines in file
:countLines
	for /f "usebackq" %%a in (`type %1 ^| find "" /v /c`) do set countLines=%%a
	exit /b

	rem count (WAR) lines in file
:countWarnings
	for /f "usebackq" %%a in (`type %1 ^| find "(WAR) " /c`) do set countLines=%%a
	exit /b

	rem delete a full directory tree, and its content, including the top directory
:deleteTree
	rem del /s /f /q %1\*.*
	rem for /f %%f in ('dir /ad /b %1\') do rd /s /q %1\%%f
	rmdir /s /q "%1" 1>nul 2>nul
	exit /b

	rem create a unique temp directory in %tempdir%
	rem expect a first argument to add to the name
:getTempDir
	set "tempdir=%TEMP%\dir-%1-%RANDOM%.tmp"
	if exist "%tempdir%" goto :getTempDir
	mkdir %tempdir%
	exit /b

	rem create a unique temp file
	rem expect a first argument to add to the name
:getTempFile
	set "tempfile=%TEMP%\file-%1-%RANDOM%.tmp"
	if exist "%tempfile%" goto :getTempFile
	exit /b

:ender
    call :color_blue "[%testbase%] %test_total% counted tests, among them %test_notok% failed"
    rem echo %test_total%-%test_ok%-%test_notok%-%test_skipped% > "%tempCounts%"
	echo [%testbase%] ending >>%mainErrors%
	exit /b

	REM https://stackoverflow.com/questions/141344/how-to-check-if-a-directory-exists-in-path/8046515#8046515
:addPath pathVar /B
	::  Safely appends the path contained within variable pathVar to the end
	::  of PATH if and only if the path does not already exist within PATH.
	::
	::  If the case insensitive /B option is specified, then the path is
	::  inserted into the front (Beginning) of PATH instead.
	::
	::  If the pathVar path is fully qualified, then it is logically compared
	::  to each fully qualified path within PATH. The path strings are
	::  considered a match if they are logically equivalent.
	::
	::  If the pathVar path is relative, then it is strictly compared to each
	::  relative path within PATH. Case differences and double quotes are
	::  ignored, but otherwise the path strings must match exactly.
	::
	::  Before appending the pathVar path, all double quotes are stripped, and
	::  then the path is enclosed in double quotes if and only if the path
	::  contains at least one semicolon.
	::
	::  addPath aborts with ERRORLEVEL 2 if pathVar is missing or undefined
	::  or if PATH is undefined.
	::
	::------------------------------------------------------------------------
	::
	:: Error checking
	if "%~1"=="" exit /b 2
	if not defined %~1 exit /b 2
	if not defined path exit /b 2
	::
	:: Determine if function was called while delayed expansion was enabled
	setlocal
	set "NotDelayed=!"
	::
	:: Prepare to safely parse PATH into individual paths
	setlocal DisableDelayedExpansion
	set "var=%path:"=""%"
	set "var=%var:^=^^%"
	set "var=%var:&=^&%"
	set "var=%var:|=^|%"
	set "var=%var:<=^<%"
	set "var=%var:>=^>%"
	set "var=%var:;=^;^;%"
	set var=%var:""="%
	set "var=%var:"=""Q%"
	set "var=%var:;;="S"S%"
	set "var=%var:^;^;=;%"
	set "var=%var:""="%"
	setlocal EnableDelayedExpansion
	set "var=!var:"Q=!"
	set "var=!var:"S"S=";"!"
	::
	:: Remove quotes from pathVar and abort if it becomes empty
	set "new=!%~1:"^=!"
	if not defined new exit /b 2
	::
	:: Determine if pathVar is fully qualified
	echo("!new!"|findstr /i /r /c:^"^^\"[a-zA-Z]:[\\/][^\\/]" ^
							   /c:^"^^\"[\\][\\]" >nul ^
	  && set "abs=1" || set "abs=0"
	::
	:: For each path in PATH, check if path is fully qualified and then
	:: do proper comparison with pathVar. Exit if a match is found.
	:: Delayed expansion must be disabled when expanding FOR variables
	:: just in case the value contains !
	for %%A in ("!new!\") do for %%B in ("!var!") do (
	  if "!!"=="" setlocal disableDelayedExpansion
	  for %%C in ("%%~B\") do (
		echo(%%B|findstr /i /r /c:^"^^\"[a-zA-Z]:[\\/][^\\/]" ^
							   /c:^"^^\"[\\][\\]" >nul ^
		  && (if %abs%==1 if /i "%%~sA"=="%%~sC" exit /b 0) ^
		  || (if %abs%==0 if /i %%A==%%C exit /b 0)
	  )
	)
	::
	:: Build the modified PATH, enclosing the added path in quotes
	:: only if it contains ;
	setlocal enableDelayedExpansion
	if "!new:;=!" neq "!new!" set new="!new!"
	if /i "%~2"=="/B" (set "rtn=!new!;!path!") else set "rtn=!path!;!new!"
	::
	:: rtn now contains the modified PATH. We need to safely pass the
	:: value accross the ENDLOCAL barrier
	::
	:: Make rtn safe for assignment using normal expansion by replacing
	:: % and " with not yet defined FOR variables
	set "rtn=!rtn:%%=%%A!"
	set "rtn=!rtn:"=%%B!"
	::
	:: Escape ^ and ! if function was called while delayed expansion was enabled.
	:: The trailing ! in the second assignment is critical and must not be removed.
	if not defined NotDelayed set "rtn=!rtn:^=^^^^!"
	if not defined NotDelayed set "rtn=%rtn:!=^^^!%" !
	::
	:: Pass the rtn value accross the ENDLOCAL barrier using FOR variables to
	:: restore the % and " characters. Again the trailing ! is critical.
	for /f "usebackq tokens=1,2" %%A in ('%%^ ^"') do (
	  endlocal & endlocal & endlocal & endlocal & endlocal
	  set "path=%rtn%" !
	)
	exit /b 0

	rem initialize a test
	rem 1. the drive and path of the test run.cmd
	rem 2. the header label
:starter
	rem get the test directory full path without trailing slash
	set testdir=%~1
	if %testdir:~-1%==\ set testdir=%testdir:~0,-1%
	rem get the basename of the directory, i.e. the name of the test
	for /F %%i in ("%testdir%") do set testbase=%%~nxi
	rem display the header of the test
    call :color_blue "[%testbase%] %~2"
	echo [%testbase%] starting >>%mainErrors%
	exit /b
