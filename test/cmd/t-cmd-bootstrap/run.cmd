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
	rem
	rem Check that cmd bootstrapping works

	call %maindir%\functions.cmd starter "%~dp0" "checking cmd bootstrapping"
	set keys=TTP_ROOTS PATH PERL5LIB TTP_NODE
	call %maindir%\functions.cmd getTempDir work
	call :clearRegistry
	call :createBootstrap
	call %maindir%\functions.cmd deleteTree %tempDir%
	call %maindir%\functions.cmd ender
	exit /b

:clearRegistry
	rem first save the initial content
	reg export HKCU\Environment %tempDir%\environment.reg /Y 1>nul
	rem then clear the keys, ignoring if they do not exist
	for %%i in (%keys%) do reg delete HKCU\Environment /v %%i /F 1>nul 2>nul
	exit /b

	rem inside of a dedicated temp directory, simulate a logon and test the boiotstrap from there
:createBootstrap
	rem create a temporary ttp.conf
	echo # created by %USER% >%tempdir%\ttp.conf
	echo %toolsdir%>>%tempdir%\ttp.conf
	echo %tempdir%>>%tempdir%\ttp.conf

	rem create an empty site tree, must have at least site.json and <node>.json
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json

	mkdir %tempdir%\etc\nodes
	echo {} > %tempdir%\etc\ttp\%COMPUTERNAME%.json

	rem after having bootstrapped, we expect to have our environment variables set
	set TTP_ROOTS=
	set TTP_NODE=
	set PERL5LIB=
	rem during development, may happen to have an empty path (oop's) so have at least the minimum required (make sure we have reg.exe)
	set "PATH=%PATH%;%SystemRoot%\system32"
	for /F "tokens=2,*" %%T in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v PATH') do call set "PATH=%%~U"
	set "systemPath=%PATH%"
	call %toolsdir%\libexec\cmd\bootstrap.cmd %tempdir%

	rem expects TTP_ROOTS=toolsdir;tempdir
	for /f "tokens=2,*" %%i in ('reg query HKCU\Environment /v TTP_ROOTS') do call set "TTP_ROOTS=%%~j"
    <NUL set /P=%BS%  [%testbase%] got TTP_ROOTS="!TTP_ROOTS!"... 
	set /A test_total+=1
	if "%TTP_ROOTS%" == "%toolsdir%;%tempdir%" (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

	rem expects PERL5LIB=toolsdir;tempdir with libexec\perl subdirs
	for /f "tokens=2,*" %%i in ('reg query HKCU\Environment /v PERL5LIB') do call set "PERL5LIB=%%~j"
    <NUL set /P=%BS%  [%testbase%] got PERL5LIB="!PERL5LIB!"... 
	set /A test_total+=1
	if "%PERL5LIB%" == "%toolsdir%\libexec\perl;%tempdir%\libexec\perl" (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

	rem expects PATH=toolsdir;tempdir with bin subdir
	for /f "tokens=2,*" %%i in ('reg query HKCU\Environment /v PATH') do call set "PATH=%%~j"
    <NUL set /P=%BS%  [%testbase%] got PATH="!PATH!"... 
	set /A test_total+=1
	if "%PATH%" == "%systemPath%;%toolsdir%\bin;%tempdir%\bin" (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

	rem expects TTP_NODE be set
	for /f "tokens=2,*" %%i in ('reg query HKCU\Environment /v TTP_NODE') do call set "TTP_NODE=%%~j"
    <NUL set /P=%BS%  [%testbase%] got TTP_NODE="!TTP_NODE!"... 
	set /A test_total+=1
	if not "%TTP_NODE%" == "" (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

	rem import the previously exported keys
	reg import %tempDir%\environment.reg 1>nul

	exit /b
