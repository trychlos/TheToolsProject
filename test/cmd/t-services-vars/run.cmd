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
	rem Check services.pl (standard) vars

	call %maindir%\functions.cmd starter "%~dp0" "checking services.pl vars"
	call %maindir%\functions.cmd getTempDir work
	set TTP_ROOTS=%toolsdir%;%tempDir%
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	mkdir %tempdir%\etc\services
	echo {} > %tempdir%\etc\ttp\site.json
	echo { "services": { "test": {}}} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	echo {} > %tempdir%\etc\services\test.json
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%

	call :checkUnknownKeyWith
	call :checkUnknownKeyWithout
	call :checkSiteKeyWith
	call :checkSiteKeyWithout
	call :checkSiteServiceKey
	call :checkSiteNodeKey
	call :checkSiteNodeServiceKey
	call :checkSeveralKeys
	call :checkCommaSeparatedKeys

	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

:checkUnknownKeyWith
	set "_command=services.pl vars -service test -key not,exist"
    <NUL set /P=%BS%  [%testbase%] testing an unknown key with service '%_command%'... 
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

:checkUnknownKeyWithout
	set "_command=services.pl vars -key not,exist"
    <NUL set /P=%BS%  [%testbase%] testing an unknown key without service '%_command%'... 
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

:checkSiteKeyWith
	echo { "TTP": { "service_key": "service_site_value" }} > %tempdir%\etc\ttp\site.json
	set "_command=services.pl vars -service test -key service_key"
    <NUL set /P=%BS%  [%testbase%] testing a site-level key with service '%_command%'... 
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
	if not "%_res%" == "service_site_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSiteKeyWithout
	set "_command=services.pl vars -key service_key"
    <NUL set /P=%BS%  [%testbase%] testing a site-level key without service '%_command%'... 
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
	if not "%_res%" == "service_site_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSiteServiceKey
	echo { "service_key": "service_value" } > %tempdir%\etc\services\test.json
	set "_command=services.pl vars -service test -key service_key"
    <NUL set /P=%BS%  [%testbase%] testing a service-level key '%_command%'... 
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
	if not "%_res%" == "service_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSiteNodeKey
	echo { "service_key": "service_node_value", "services": { "test": { "service_key": "node_service_value" }}} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	set "_command=services.pl vars -key service_key"
    <NUL set /P=%BS%  [%testbase%] testing a node-overriden key '%_command%'... 
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
	if not "%_res%" == "service_node_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSiteNodeServiceKey
	set "_command=services.pl vars -service test -key service_key"
    <NUL set /P=%BS%  [%testbase%] testing a node-service-overriden key '%_command%'... 
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
	if not "%_res%" == "node_service_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkSeveralKeys
	echo { "TTP": { "service_key1": { "service_key2": { "service_key3": "service123_value" }}}} > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	echo {} > %tempdir%\etc\services\test.json
	set "_command=services.pl vars -key service_key1 -key service_key2 -key service_key3"
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
	if not "%_res%" == "service123_value" (
		call :error %_command%
		exit /b
	)
	@echo %_res% - OK
	set /A test_ok+=1
	exit /b

:checkCommaSeparatedKeys
	set "_command=services.pl vars -key service_key1,service_key2,service_key3"
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
	if not "%_res%" == "service123_value" (
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
	<NUL set /P=%BS%  service: >> %mainErrors%
	type %tempdir%\etc\services\test.json >> %mainErrors%
	exit /b
