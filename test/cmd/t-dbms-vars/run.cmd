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
	rem Check dbms.pl (standard) vars

	call %maindir%\functions.cmd starter "%~dp0" "checking dbms.pl vars"
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%
	call :checkListVars
	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

:checkListVars
	for /F "tokens=2,* delims=] " %%A in ('dbms.pl vars ^| findstr /C:"--" ^| findstr /V "help colored dummy verbose key"') do call :checkVar %%A
	exit /b

:checkVar
	set _keyword=%1
    <NUL set /P=%BS%  [%testbase%] testing 'dbms.pl vars -%_keyword%'... 

	dbms.pl vars --%_keyword% | findstr /V WAR 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_keyword%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_keyword%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_keyword%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	echo %_res% OK
	set /A test_ok+=1
	exit /b

:error
	call %maindir%\functions.cmd color_red "NOT OK"
	set /A test_notok+=1
	echo dbms.pl vars %1 >> %mainErrors%
	type %stdout% >> %mainErrors%
	type %stderr% >> %mainErrors%
	exit /b
