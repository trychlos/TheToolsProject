@echo off
	rem this script is run from a workload.cmd: we do not need here to care about a logfile
	set _time=%TIME: =0%
	set STARTUP=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %_time:~0,2%:%_time:~3,2%:%_time:~6,2%
	mqtt.pl publish -nocolored -topic %COMPUTERNAME%/startup/at -payload "%STARTUP%" -retain
	ttp.pl alert -nocolored -message "%COMPUTERNAME% startup at %STARTUP%" -level NOTICE
    exit /b
