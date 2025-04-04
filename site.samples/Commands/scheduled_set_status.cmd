@echo off
	rem Set the status of a task
	rem Expected arguments:
	rem 1. a task name
	rem 2. the desired task status as /Enable | /Disable
	set ME=[%~nx0]
	call :setLogFile %~n0
	set argC=0
	for %%x in (%*) do set /A argC+=1
	if not %argC% == 2 (
		call :logMe ERR expected 2 TaskName and TaskStatus arguments, found %argC%
		exit /b 1
	)
	if %2 neq /Enable (
		if %2 neq /Disable (
			call :logMe ERR expected arg2=/Enable, /Disable, found "%2"
			exit /b 1
		)
	)
	set task=%1
	set status=%2
	call :doExecute %*
	exit /b

:doExecute
	call :logMe ++ executing %~f0, setting "%task%" task status to "%status%"
	schtasks /Change /TN %task% %status%
	set rc=%ERRORLEVEL%
	if %rc% == 0 (
		call :logMe done
	) else (
		call :logMe NOT OK
	)
    exit /b %rc%

:logShort
	echo.  %*
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %ME% %* >>%LOGFILE%
	exit /b

:logMe
	echo %ME% %*
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %ME% %* >>%LOGFILE%
	exit /b

:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsCommands -nocolored') do @set _logsdir=%%a
	set _time=%TIME: =0%
	set LOGFILE=%_logsdir%\\%1.log
	exit /b
