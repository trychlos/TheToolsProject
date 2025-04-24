@echo off
	rem The Tools Project - Tools System and Working Paradigm for IT Production
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
	rem Check for standard perl modules

	call %maindir%\functions.cmd starter "%~dp0" "checking for standard Perl modules in '%toolsdir%'""
	call :checkModules
	call %maindir%\functions.cmd ender
	exit /b

:checkModules
	for /F "usebackq delims=" %%i in (`powershell "Get-ChildItem -Recurse $Env:toolsdir\*.p? | Select-String -Pattern '^\s*use\s','^\s*require\s' | Select-String -Pattern 'TTP','use\s+warnings','use\s+constant','use\s+open','use\s+overload','use\s+strict','use\s+utf8','global\s+qw' -NotMatch | ForEach-Object { if( $_.Line -match 'if \$Config{osname}' ){ $_.Line.split( ' ' )[5] } else { $_.Line.split( ' ' )[1] } } | ForEach-Object { $_.Replace( ';', '' ).Replace( ',', '' ) } | Sort-Object | Get-Unique"`) do call :isRelevant %%i
	exit /b

:isRelevant
	set _pck=%*
	rem remove surronding double quotes
	set "_pck=%_pck:"=%"

	rem test whether the perl module is present
	<NUL set /P=%BS%  [%testbase%] testing !_pck!... 
	perl -e "use %_pck%;" 1>nul 2>&1
	set _rc=%ERRORLEVEL%
	set /A test_total+=1

    if %_rc%==0 (
        echo OK
        set /A test_ok+=1

	) else (
        call %maindir%\functions.cmd color_red "NOT OK"
		perl -e "use %_pck%;" 1>>"%mainErrors%" 2>&1
        set /A test_notok+=1
    )

	exit /b