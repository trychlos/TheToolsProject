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
