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
	rem Check that TTP Perl modules are each individually loadable

	call %maindir%\functions.cmd starter "%~dp0" "checking that TTP Perl modules are each individually loadable"
	set usedByNode=TTP::IAcceptable TTP::IEnableable TTP::IFindable TTP::IJSONable
	call :checkModules
	call %maindir%\functions.cmd ender
	exit /b

:checkModules
	for /F "usebackq delims=" %%i in (`dir /B /S !toolsdir!\*.pm`) do call :isRelevant %%i
	exit /b

:isRelevant
	set _pckpm=%*
	rem @echo isRelevant !_pckpm!

	rem translate a module file path path/A/B/C.pm into a module name A::B::C
	set "_pck=!_pckpm!"
	set "_pck=!_pck:%toolsdir%\libexec\perl\=!"
	set "_pck=!_pck:.pm=!"

	REM Step 1: Replace remaining \ with ::
	set "_pck=!_pck:\=#!"
:replace_loop
	if "!_pck!"=="!_pck:#=::!" goto done_replace
	set "_pck=!_pck:#=::!"
	goto replace_loop
:done_replace
	rem @echo _pck=!_pck!

	rem test if the module is loadable by itself
    <NUL set /P=%BS%  [%testbase%] use'ing !_pck!... 
	set /A test_total+=1

	rem test for exclusion list
	set isExcluded=0

	REM Loop through exclusions and compare
	for %%M in (%usedByNode%) do (
		if "%%M"=="%_pck%" (
			set isExcluded=1
		)
	)

	if %isExcluded% == 0 (
		perl -e "use %_pck%;" 1>nul 2>nul
		set _rc=%ERRORLEVEL%

		if !_rc! == 0 (
			echo OK
			set /A test_ok+=1

		) else (
			call %maindir%\functions.cmd color_red "NOT OK"
			perl -e "use %_pck%;" 1>>"%mainErrors%" 2>&1
			set /A test_notok+=1
		)

	) else (
		call %maindir%\functions.cmd color_cyan "skipped as use.d by Node/Site"
		set /A test_skipped+=1
	)

	exit /b
