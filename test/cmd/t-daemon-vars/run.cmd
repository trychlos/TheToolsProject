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
	rem Check daemon.pl (standard) vars

	call %maindir%\functions.cmd starter "%~dp0" "checking daemon.pl vars"
	call %maindir%\functions.cmd getTempDir work
	set TTP_ROOTS=%toolsdir%;%tempDir%
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	mkdir %tempdir%\etc\daemons
	echo {} > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	echo {} > %tempdir%\etc\daemons\test.json
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%

	call :checkStandardVars
	call :checkUnknownKey
	call :checkUnknownName
	call :checkAnyKey
	call :checkSeveralKeys
	call :checkCommaSeparatedKeys

	call %maindir%\functions.cmd deleteTree %tempDir%
	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

:checkStandardVars
	for /F "tokens=2,* delims=] " %%A in ('daemon.pl vars ^| findstr /C:"--" ^| findstr /V "help colored dummy verbose key"') do call :checkVar %%A
	exit /b

:checkVar
	set "_command=daemon.pl vars -%1"
    <NUL set /P=%BS%  [%testbase%] testing '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_command%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkUnknownKey
	set "_command=daemon.pl vars -name test -key not,exist"
    <NUL set /P=%BS%  [%testbase%] testing an unknown key '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_command%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	if not "%_res%" == "(undef)" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkUnknownName
	set "_command=daemon.pl vars -name unknown -key anything"
    <NUL set /P=%BS%  [%testbase%] testing an unknown name '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 1 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 2 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	@echo OK
	set /A test_ok+=1
	exit /b

:checkAnyKey
	echo { "daemon_key": "daemon_value" } > %tempdir%\etc\daemons\test.json
	set "_command=daemon.pl vars -name test -key daemon_key"
    <NUL set /P=%BS%  [%testbase%] testing a daemon key '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_command%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	if not "%_res%" == "daemon_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSeveralKeys
	echo { "level1": { "level2": { "level3": "level123_value" }}} > %tempdir%\etc\daemons\test.json
	set "_command=daemon.pl vars -name test -key level1 -key level2 -key level3"
    <NUL set /P=%BS%  [%testbase%] testing several specifications of keys '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_command%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	if not "%_res%" == "level123_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkCommaSeparatedKeys
	set "_command=daemon.pl vars -name test -key level1,level2,level3"
    <NUL set /P=%BS%  [%testbase%] testing a comma-separated list of keys '%_command%'... 
	%_command% 2>%stderr% | findstr /V WAR 1>%stdout%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
	if not %_rc% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stderr%
	if not %countLines% == 0 (
		call :error %_command%
		exit /b
	)
	call %maindir%\functions.cmd countLines %stdout%
	if not %countLines% == 1 (
		call :error %_command%
		exit /b
	)
	for /F "tokens=2,* delims= " %%A in (%stdout%) do set _res=%%A
	if not "%_res%" == "level123_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:error
	call %maindir%\functions.cmd color_red "%_res% - NOT OK"
	set /A test_notok+=1
	echo %1 >> %mainErrors%
	type %stdout% >> %mainErrors%
	type %stderr% >> %mainErrors%
	<NUL set /P=%BS%  site: >> %mainErrors%
	type %tempdir%\etc\ttp\site.json >> %mainErrors%
	<NUL set /P=%BS%  node: >> %mainErrors%
	type %tempdir%\etc\nodes\%COMPUTERNAME%.json >> %mainErrors%
	<NUL set /P=%BS%  daemon: >> %mainErrors%
	type %tempdir%\etc\daemons\test.json >> %mainErrors%
	exit /b
