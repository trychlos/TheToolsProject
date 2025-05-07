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
	rem Check that TTP Perl modules are there, not mispelled, loadable

	call %maindir%\functions.cmd starter "%~dp0" "checking that TTP Perl modules are rightly use'd or require'd"
	call :checkModules
	call %maindir%\functions.cmd ender
	exit /b

:checkModules
	for /F "usebackq delims=" %%i in (`powershell "Get-ChildItem -Recurse $Env:toolsdir\*.p? | Select-String -Pattern '^\s*use\s+TTP','^\s*require\s+TTP'"`) do call :isRelevant %%i
	exit /b

:isRelevant
	set _pck=%*
	rem @echo isRelevant %_pck%

	REM Step 1: Extract includer, line number, and code (rest)
	for /f "tokens=1,2* delims=:" %%A in ("!_pck!") do (
		set "includer=%%A"
		set "linenumber=%%B"
		set "code=%%C"
	)

	REM Step 2: Trim leading spaces from code
	for /f "tokens=* delims= " %%X in ("!code!") do (
		set "trimmed=%%X"
	)

	REM Step 3: Extract the module name after use/require
	for /f "tokens=1,2 delims= " %%U in ("!trimmed!") do (
		set "keyword=%%U"
		set "included=%%V"
	)

	rem remove trailing semi-colon
	if "!included:~-1!"==";" set "included=!included:~0,-1!"

	rem translate a module name 'A::B::C' into a module filepath 'A/B/C.pm'
	REM Step 1: Replace :: with \
	set "file=!included::=#!"
:replace_loop
	if "!file!"=="!file:#=\!" goto done_replace
	set "file=!file:#=\!"
	goto replace_loop
:done_replace
	set "file=!toolsdir!\libexec\perl\!file!.pm"

	rem @echo Includer: !includer!
	rem @echo Included: !included!
	rem @echo file: !file!

	rem test whether the perl module is present
	<NUL set /P=%BS%  [%testbase%] required from '!includer!': !included!... 
	set /A test_total+=1

	if exist !file! (
        echo OK
        set /A test_ok+=1

	) else (
        call %maindir%\functions.cmd color_red "NOT OK"
		echo!file! is not readable" >> "%mainErrors%"
        set /A test_notok+=1
	)

	exit /b
