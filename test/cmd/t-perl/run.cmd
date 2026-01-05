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
	rem Check for perl, displaying the Perl version

	call %maindir%\functions.cmd starter "%~dp0" "checking we do have a perl executable"
	if %test_notok% == 0 call :checkAddressable
	if %test_notok% == 0 call :checkVersion
	call %maindir%\functions.cmd ender
	exit /b

:checkAddressable
	<NUL set /P=%BS%  [%testbase%] checking that perl is addressable... 

	set _foo=
	for /f %%g in ('where perl 2^>nul') do set _foo=%%g
	set /a test_total+=1

	if "%_foo%" == "" (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /a test_notok+=1
		echo "where perl: ">>"%mainErrors%"
		where perl >>"%mainErrors%" 2>&1

	) else (
		echo %_foo% - OK
		set /a test_ok+=1
	)
	exit /b

:checkVersion
	<NUL set /P=%BS%  [%testbase%] checking for perl version... 

	set _foo=
	for /f "tokens=9,* delims=() " %%g in ('perl -v ^| findstr /c:"This is perl"') do set _foo=%%g
	set /a test_total+=1

	if "%_foo%" == "" (
		call %maindir%\functions.cmd color_red "NOT OK"
		set /a test_notok+=1

	) else (
		echo %_foo% - OK
		set /a test_ok+=1
	)
	exit /b
