@echo off
	rem Copyright (C) 2023-2025 PWI Consulting for Inlingua
	rem
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
	rem TTP bootstrapping
	rem call C:\INLINGUA\TheToolsProject\tools\libexec\cmd\bootstrap.cmd
	rem
	rem this .cmd is expected to be called with the workload name as unique argument, may have until 8 additional arguments to be passed to underlying commands
	rem e.g. "C:\INLINGUA\Scripts\cmds\workload.cmd daily.morning -dummy"
	rem Note 1: this workload.cmd adds itself the -nocolored option to every run command. You should take care that the run commands accept (if not honor) this command-line option.

	set ME=[%~nx0 %1]
	call :setLogFile %1
	call :doExecute %* >>%LOGFILE% 2>&1
	exit /b

:doExecute
	call :logLine executing %~f0 %*
	set i=0
	for /f "tokens=*" %%C in ('services.pl list -workload %1 -commands -hidden %2 %3 %4 %5 %6 %7 %8 %9 -nocolored ^| findstr /V "[services.pl list]"') do call :doCommand %%C %2 %3 %4 %5 %6 %7 %8 %9
	%~dp0\\workload_summary.pl -workload %1 -commands res_command -start res_start -end res_end -rc res_rc -count %i% %2 %3 %4 %5 %6 %7 %8 %9 -nocolored
    exit /b

:doCommand
	rem - have a timestamped line before running each command
	rem - prepare the end summary
	set /A i=i+1
	set res_command[%i%]=%*
	set res_start[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	call :logLine %*
	%*
	call :logLine RC=%ERRORLEVEL%
	set res_rc[%i%]=%ERRORLEVEL%
	set res_end[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	exit /b

:logLine
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %ME% %*
	exit /b

rem compute the log pathname as 'C:\myDir\dailyLogs\250521\TTP\WS12DEV1-daily.morning-20250521-050002.log'
:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsCommands -nocolored') do @set _logsdir=%%a
	set _time=%TIME: =0%
	set LOGFILE=%_logsdir%\\%COMPUTERNAME%-%1-%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%-%_time:~0,2%%_time:~3,2%%_time:~6,2%.log
	exit /b
