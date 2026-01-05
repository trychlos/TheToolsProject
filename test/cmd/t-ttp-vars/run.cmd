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
	rem Check ttp.pl (standard) vars

	call %maindir%\functions.cmd starter "%~dp0" "checking ttp.pl vars"
	call %maindir%\functions.cmd getTempDir work
	set TTP_ROOTS=%toolsdir%;%tempDir%
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%

	call :checkStandardVars
	call :checkUnknownKey
	call :checkSiteLevelWithSite
	call :checkSiteLevelWithoutSite
	call :checkGlobalWithTTP
	call :checkGlobalWithoutTTP
	call :checkGlobalWithoutToops
	call :checkNodeOverridenTTP
	call :checkNodeOverridenSite
	call :checkSeveralKeys
	call :checkCommaSeparatedKeys

	call %maindir%\functions.cmd deleteTree %tempDir%
	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

:checkStandardVars
	for /F "tokens=2,* delims=] " %%A in ('ttp.pl vars ^| findstr /C:"--" ^| findstr /V "help colored dummy verbose key"') do call :checkVar %%A
	exit /b

:checkVar
	set "_command=ttp.pl vars -%1"
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
	set "_command=ttp.pl vars -key not,exist"
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

:checkSiteLevelWithSite
	echo { "site": { "site_key": "site_site_value" }} > %tempdir%\etc\ttp\site.json
	set "_command=ttp.pl vars -key site,site_key"
    <NUL set /P=%BS%  [%testbase%] testing a site-level key with site prefix '%_command%'... 
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
	if not "%_res%" == "site_site_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSiteLevelWithoutSite
	set "_command=ttp.pl vars -key site_key"
    <NUL set /P=%BS%  [%testbase%] testing a site-level key without site prefix '%_command%'... 
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

:checkGlobalWithTTP
	echo { "TTP": { "ttp_key": "site_ttp_value" }} > %tempdir%\etc\ttp\site.json
	set "_command=ttp.pl vars -key TTP,ttp_key"
    <NUL set /P=%BS%  [%testbase%] testing a TTP global key with TTP prefix '%_command%'... 
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
	if not "%_res%" == "site_ttp_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkGlobalWithoutTTP
	set "_command=ttp.pl vars -key ttp_key"
    <NUL set /P=%BS%  [%testbase%] testing a TTP global key witout any prefix on TTP-based '%_command%'... 
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
	if not "%_res%" == "site_ttp_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkGlobalWithoutToops
	echo { "toops": { "ttp_key": "site_ttp_value" }} > %tempdir%\etc\ttp\site.json
	set "_command=ttp.pl vars -key ttp_key"
    <NUL set /P=%BS%  [%testbase%] testing a TTP global key witout any prefix on toops-based '%_command%'... 
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
	if not "%_res%" == "site_ttp_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkNodeOverridenTTP
	echo { "ttp_key": "node_ttp_value", "site_key": "node_site_value" } > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	set "_command=ttp.pl vars -key ttp_key"
    <NUL set /P=%BS%  [%testbase%] testing a node-overriden TTP key '%_command%'... 
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
	if not "%_res%" == "node_ttp_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkNodeOverridenSite
	set "_command=ttp.pl vars -key site_key"
    <NUL set /P=%BS%  [%testbase%] testing a node-overriden site-level key '%_command%'... 
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
	if not "%_res%" == "node_site_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSeveralKeys
	echo { "site": { "site_key": { "site_sublevel": "site_key_sublevel_value" }}} > %tempdir%\etc\ttp\site.json
	set "_command=ttp.pl vars -key site -key site_key -key site_sublevel"
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
	if not "%_res%" == "site_key_sublevel_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkCommaSeparatedKeys
	set "_command=ttp.pl vars -key site,site_key,site_sublevel"
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
	if not "%_res%" == "site_key_sublevel_value" (
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
	exit /b
