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
	rem Check for all commands and verbs standard options

	call %maindir%\functions.cmd starter "%~dp0" "checking TTP standard commands and verbs options"

	rem dynamically build a temporary working environment
	call %maindir%\functions.cmd getTempDir work
	call %maindir%\functions.cmd getTempFile out
	set stdout=%tempFile%
	call %maindir%\functions.cmd getTempFile err
	set stderr=%tempFile%
	mkdir %tempdir%\etc\nodes
	mkdir %tempdir%\etc\ttp
	echo {} > %tempdir%\etc\ttp\site.json
	echo {} > %tempdir%\etc\nodes\%COMPUTERNAME%.json
	rem create a temporary ttp.conf
	echo # created by %USER% >%tempDir%\ttp.conf
	echo %toolsdir%>>%tempDir%\ttp.conf
	echo %tempDir%>>%tempDir%\ttp.conf
	rem bootstrap this temporary environment
	call %toolsdir%\libexec\cmd\bootstrap.cmd %tempdir%

	call :getCommandsList

	rem restore the runtime environment before quitting
	call %toolsdir%\libexec\cmd\bootstrap.cmd
	call %maindir%\functions.cmd deleteTree %tempDir%
	call %maindir%\functions.cmd ender
	del /S /F /Q %stdout% 1>nul 2>nul
	del /S /F /Q %stderr% 1>nul 2>nul
	exit /b

	rem getting the list of commands
:getCommandsList
    <NUL set /P=%BS%  [%testbase%] getting the list of commands... 
	ttp.pl list -commands 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
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
	if %count_failed% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

    <NUL set /P=%BS%  [%testbase%] verifying the count of commands... 
	set /A test_total+=1
	for /f "usebackq" %%a in (`type %stdout% ^| find "[ttp.pl list]" /v /c`) do set countLines=%%a
	for /f "usebackq tokens=3,*" %%a in (`type %stdout% ^| find "found command"`) do set countCommands=%%a
	if %countLines% == %countCommands% (
		echo found %countCommands% - OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
		echo got countLines=%countLines% >> %mainErrors%
		echo got countCommands=%countCommands% >> %mainErrors%
	)

	rem iterate on every command
	for /f "usebackq tokens=1,* delims=: " %%a in (`type %stdout% ^| find "[ttp.pl list]" /v`) do call :checkCommand %%a

	exit /b

	rem check all verbs of a command
	rem 1. the command
:checkCommand
	set "_command=%1"
    <NUL set /P=%BS%  [%testbase%] getting the list of '%_command%' available verbs... 
	%_command% 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
	set /A test_total+=1
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
	if %count_failed% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

    <NUL set /P=%BS%  [%testbase%] verifying the count of '%_command%' verbs... 
	set /A test_total+=1
	for /f "usebackq" %%a in (`type %stdout% ^| find "%_command%" /v /c`) do set countLines=%%a
	for /f "usebackq tokens=2,*" %%a in (`type %stdout% ^| find "found verb"`) do set countVerbs=%%a
	if %countLines% == %countVerbs% (
		echo found %countVerbs% - OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
		type %stdout% >> %mainErrors%
		echo got countLines=%countLines% >> %mainErrors%
		echo got countVerbs=%countVerbs% >> %mainErrors%
	)

	rem ask help for every verb
	for /f "usebackq tokens=1,* delims=: " %%a in (`type %stdout% ^| find "%_command%" /v`) do call :checkVerb %_command% %%a

	exit /b

	rem check a verb help
	rem 1. the command
	rem 2. the verb
:checkVerb
	set "_command=%1"
	set "_verb=%2"
    <NUL set /P=%BS%  [%testbase%] checking that '%_command% %_verb%' displays standard help... 
	set /A test_total+=1
	%_command% %_verb% 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
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
	if %count_failed% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

    <NUL set /P=%BS%  [%testbase%] checking that '%_command% %_verb%' accepts standard options... 
	set /A test_total+=1
	%_command% %_verb% -help -dummy -verbose -colored 1>%stdout% 2>%stderr%
	set _rc=%ERRORLEVEL%
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
	if %count_failed% == 0 (
		echo OK
		set /A test_ok+=1
	) else (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /A test_notok+=1
	)

	exit /b
