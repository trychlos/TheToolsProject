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
	rem Check for TTP bootstrapping when site.json or node.json are not present

	call %maindir%\functions.cmd starter "%~dp0" "checking TTP bootstrapping"
	call %maindir%\functions.cmd getTempDir work
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%
	set TTP_ROOTS=%toolsdir%;%tempDir%
	call :checkNoSite
	call :checkNoNode
	call :checkSiteAndNode
	call :checkMalformedSite
	call :checkWellformedSite
	call :checkMalformedNode
	call :checkSiteVariants
	call %maindir%\functions.cmd deleteTree %tempDir%
	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

	rem what happens if we do not find any ttp/site.json ?
:checkNoSite
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] without any site.json, checking that stdout is empty... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stdout%
	if %countLines% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] without any site.json, checking for expected error messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 3 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] without any site.json, checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 1 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem have an empty ttp/site.json, expects an error for no <node>.json
:checkNoNode
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] without any ^<node^>.json, checking that stdout is empty... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stdout%
	if %countLines% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] without any ^<node^>.json, checking for expected error messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 2 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] without any ^<node^>.json, checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 1 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem have an empty ttp/site.json and an empty <node>.json, expects a normal output
:checkSiteAndNode
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] checking for a normal stdout... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stdout%
	if %countLines% gtr 5 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] checking for an empty stderr... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem have a malformed site.json (e.g. not a json)
:checkMalformedSite
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo azerty > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] with a malformed site.json, checking expected warning messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countWarnings %stdout%
	if %countLines% == 2 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with a malformed site.json, checking for expected error messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 3 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with a malformed site.json, checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 1 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem have a wellformed site.json with unexpected keys
:checkWellformedSite
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo { "key": "value" } > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] with unexpected keys, checking stdout is empty... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stdout%
	if %countLines% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with unexpected keys, checking for expected error messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 3 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with unexpected keys, checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 1 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem have a malformed <node>.json (e.g. not a json)
:checkMalformedNode
	call %maindir%\functions.cmd deleteTree %tempDir%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json
	echo my-malformed-node-json > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	ttp.pl 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
    <NUL set /P=%BS%  [%testbase%] with a malformed ^<node^>.json, checking expected warning messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countWarnings %stdout%
	if %countLines% == 2 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with a malformed ^<node^>.json, checking for expected error messages... 
	set /A test_total+=1
	call %maindir%\functions.cmd countLines %stderr%
	if %countLines% == 2 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stderr% >> %mainErrors%
	)
    <NUL set /P=%BS%  [%testbase%] with a malformed ^<node^>.json, checking return code of the command... 
	set /A test_total+=1
	if %_rc% == 1 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		echo got rc=%_rc% >> %mainErrors%
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b

	rem check that all accepted site variants actually work
	rem list from TTP::Site::$Const->{finder}{dirs} - etc/ttp/site.json has already been tested
:checkSiteVariants
	set site_variants=etc\site.json etc\toops.json etc\ttp.json etc\toops\site.json etc\toops\toops.json etc\toops\ttp.json etc\ttp\toops.json etc\ttp\ttp.json
	for %%f in (%site_variants%) do (
		rem cleanup the working environment
		call %maindir%\functions.cmd deleteTree %tempDir%
		mkdir %tempdir%\etc\nodes
		mkdir %tempdir%\etc\toops
		mkdir %tempdir%\etc\ttp
		del /f /q %stdout% 1>nul 2>nul
		del /f /q %stderr% 1>nul 2>nul
		rem setup the to-be tested file
		echo {} > %tempdir%\%%f
		echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
		ttp.pl 1>%stdout% 2>%stderr%
		set _rc=!ERRORLEVEL!
		rem check the result
		rem @echo on
		set count_failed=0
		call %maindir%\functions.cmd countLines %stdout%
		if !countLines! == 0 (
			set /A count_failed+=1
			type %stdout% >> %mainErrors%
		)
		call %maindir%\functions.cmd countLines %stderr%
		if !countLines! gtr 0 (
			set /A count_failed+=1
			type %stderr% >> %mainErrors%
		)
		if !_rc! gtr 0 (
			set /A count_failed+=1
			echo rc=!_rc! >> %mainErrors%
		)
		rem and display
		<NUL set /P=%BS%  [%testbase%] checking that '%%f' is accepted... 
		set /A test_total+=1
		rem @echo count_failed=!count_failed!
		if !count_failed! == 0 (
			echo OK
			set /A test_ok+=1
		) else (
			call %maindir%\functions.cmd color_red "NOT OK"
			set /A test_notok+=1
			rem type %stdout%
			rem type %stderr%
			rem echo rc=!_rc!
		)
	)
	del /f /q %stdout%
	del /f /q %stderr%
	exit /b
