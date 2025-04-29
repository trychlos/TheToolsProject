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
	rem Just run:
	rem     $ test/run.sh
	rem or:
	rem     C:\> test\run.cmd
	rem
	rem Tests are executed with the current git branch.
	rem
	rem have to test:
	rem - for Perl standard modules
	rem - for Perl TTP modules
	rem - sh bootstrapping
	rem - ttp bootstrapping
	rem cmd bootstrapping
	rem - we do not have a site.json
	rem - we do not have a node.json
	rem - $ ttp.pl: gives a list exit=0
	rem - $ ttp.pl list: gives an help, exit=0
	rem - $ ttp.pl list -commands, gives a list, exit=0
	rem $ ttp.pl push -noverb
	rem $ ttp.pl vars -logsRoot
	rem $ ttp.pl vars -key logs,rootDir
	rem tests for daemons

	rem https://stackoverflow.com/questions/27802376/create-unique-file-name-windows-batch
	rem https://ss64.com/nt/setlocal.html
	setlocal EnableDelayedExpansion
	setlocal EnableExtensions 

	rem get the path of this script without the trailing slash
	set maindir=%~dp0
	if %maindir:~-1%==\ set maindir=%maindir:~0,-1%

	rem compute once the tools/ directory Path
	call :toolsdir

	rem initialize global counters
	set main_total=0
	set main_ok=0
	set main_notok=0
	set main_skipped=0

	rem create temp files
	call %maindir%\functions.cmd getTempFile errors
	set mainErrors=%tempFile%
	echo > %mainErrors%
	
	rem https://stackoverflow.com/questions/9864620/in-batch-how-do-i-create-spaces-at-the-beginning-of-a-input-prompt-string
	::define a variable containing a single backspace character
	for /f %%A in ('"prompt $H &echo on &for %%B in (1) do rem"') do set BS=%%A

	rem List of test directories
	rem set test_dirs=t-perl t-perl-std t-ttp-case t-ttp-load t-cmd-bootstrap t-ttp-bootstrap t-pl-commands
	set test_dirs=t-cmd-bootstrap

	for %%D in (%test_dirs%) do (
		if exist %maindir%\%%D\run.cmd (
			rem initialize test counters
			set test_total=0
			set test_ok=0
			set test_notok=0
			set test_skipped=0
			rem run the test
			call %maindir%\%%D\run.cmd
			rem increment main counters
			set /A main_total+=!test_total!
			set /A main_ok+=!test_ok!
			set /A main_notok+=!test_notok!
			set /A main_skipped+=!test_skipped!
		) else (
			set /A main_total+=1
			set /A main_skipped+=1
			echo [run.cmd] %%D: no run.cmd available, passing
		)
	)

	echo [run.cmd] counted !main_total! total tests, among them !main_skipped! skipped, and !main_notok! failed

	if !main_notok! gtr 0 (
		echo Error summary:
		for /f "usebackq delims=" %%L in ("%mainErrors%") do (
			<NUL set /P=%BS%   %%L
		)
	)

	del /f /q %mainErrors%
	endlocal
	exit /b

:toolsdir
	for /f "tokens=*" %%i in ('powershell "$Env:maindir | Split-Path -Parent | Split-Path -Parent"') do set toolsdir=%%i
	set toolsdir=%toolsdir%\tools
	exit /b
