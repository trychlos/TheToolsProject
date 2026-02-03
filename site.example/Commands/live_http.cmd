@echo off
	rem 1 this script is run from 'services.pl live' verb
	rem 2 expects parameters as:
	rem   - 1: service name
	rem   - 2: environment
	rem   - 3: URL
	if [%3] == [] goto error
	for /f "tokens=2" %%A in ('http.pl get -nocolored -url %3 -header X-Sent-By -accept ... ^| findstr X-Sent-By') do echo %%A
	exit /b

:error
	echo [ERROR] usage: %0 ^<SERVICE^> ^<ENVIRONMENT^> ^<URL^>
	exit /b 1
