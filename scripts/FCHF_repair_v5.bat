@echo off
setlocal enabledelayedexpansion
set serviceName=FileCatalystHotFolder
set servicePath=C:\Program Files\FileCatalyst HotFolder
set tempPath=C:\temp
set drivePath=\\network\path\to\FileCatalyst Configs
set sourcePath=H:
set flagFile=C:\temp\_filesCopied.flag
set restarts=1
set checks=1
set brokenConfigs=TRUE
set fileSize=0

:: Change the domain\service_account & Password in hex format
:: Change the network adapter name "MAIN" 

:-------------------------------------
REM Check if service exists
sc query %serviceName% >nul 2>&1
if %errorlevel% NEQ 0 (
	echo [101;93m FATAL [0m: Service %serviceName% does not exist.
	choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul 
	exit /B 1
)

REM Check if files have already been copied
if exist "%flagFile%" (
	echo [7m INFO [0m: Files have already been copied.
	goto BatchGotAdmin
)

:: Copy FileCatalyst Configs to a temp folder with current user account
:-------------------------------------
net use H: "%drivePath%" /user:domain\service_account Password in hex format /persistent:no >nul 2>&1

copy "%sourcePath%\*.xml" "%tempPath%\" /Y
if %errorlevel%==0 (
    echo [7m INFO [0m: XML files copied successfully.
) else (
    echo [101;93m FATAL [0m: Error copying XML files. Restart the batch script or check the RCS network connection.
	choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
	EXIT /B 1
)

copy "%sourcePath%\fchf.conf" "%tempPath%\" /Y
if %errorlevel%==0 (
    echo [7m INFO [0m: Configuration file copied successfully.
) else (
    echo [101;93m FATAL [0m: Error copying configuration file. Restart the batch script or check the RCS network connection.
	choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
	EXIT /B 1
)

REM Flag to indicate files have been copied
echo Files copied > "%flagFile%"
attrib +h "%flagFile%"

echo off
: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"
	goto main
:--------------------------------------

:main

REM Restart FileCatalyst service
:stopService
echo [7m INFO [0m: Stopping %serviceName% service...
sc stop %serviceName% >nul

REM Check for *.error.* files
:checkError
if exist "%servicePath%\*.error.*" (
	echo [7m INFO [0m: Error files found in %servicePath%. Deleting .error. files...
	set brokenConfigs=TRUE
	del "%servicePath%\*.error.*" /Q
	if %errorlevel%==0 (
		echo [7m INFO [0m: All error files deleted successfully.
		goto replaceConfigs
	) 
	if %errorlevel%==1062 (
		echo [7m INFO [0m: All error files deleted successfully.
		goto replaceConfigs
	)
	echo [101;93m FATAL [0m: Error deleting error files. Please remove .error. files manually.
	echo [7m INFO [0m: Open PowerShell as an administrator and Run the following commands:
	echo -------------------------------------------------------------------------------------[97m
	echo cd C:\Program Files\FileCatalyst HotFolder
	echo Get-ChildItem -Filter '*.error.*' ^| Remove-Item
	echo [0m-------------------------------------------------------------------------------------
	choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
	EXIT /B 1
) else (
	echo [7m INFO [0m: No error files found in %servicePath%.
)

:setInterface

rem Get the IP address of the network adapter named "MAIN"
for /f "tokens=3 delims=: " %%I in ('netsh interface IPv4 show addresses "MAIN" ^| findstr /C:"IP Address"' ) do set IPAddr=%%I
if [!IPAddr!] EQU [] (
	echo [103;90m WARN [0m: Failed to get the IP address of the network adapter named "MAIN".
	echo [7m INFO [0m: Set IPv4 address to localhost...
	set IPAddr=127.0.0.1
)

echo [7m INFO [0m: Identified local IPv4 address: %IPAddr%.


rem Update the fchf.conf file using PowerShell
powershell.exe -Command "& {(Get-Content %tempPath%\fchf.conf) -replace 'FC.hotfolder.config.admin.web.hostname=.*', 'FC.hotfolder.config.admin.web.hostname=%IPAddr%' -replace 'FC.hotfolder.config.admin.web.ip=.*', 'FC.hotfolder.config.admin.web.ip=%IPAddr%' | Out-File -encoding ASCII %tempPath%\fchf.conf}"
if %errorlevel% NEQ 0 (
    echo [103;90m WARN [0m: Failed to replace FileCatalyst Interface IPv4 address.
	echo [103;90m WARN [0m: Please update fchf.conf manually:
	echo -------------------------------------------------------------------[97m
	echo line 118: FC.hotfolder.config.admin.web.hostname=%IPAddr%
	echo line 119: FC.hotfolder.config.admin.web.ip=%IPAddr%
	echo [0m-------------------------------------------------------------------
	choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
)

REM Replace FileCatalyst Config Files
:replaceConfigs
if "%brokenConfigs%"=="TRUE" (
	echo [7m INFO [0m: Replacing configs...
	copy "%tempPath%\*.xml" "%servicePath%\" /Y
	copy "%tempPath%\fchf.conf" "%servicePath%\" /Y
	set brokenConfigs=FALSE
	echo [7m INFO [0m: Files copied. Attempting to start the service again...
	sc start %serviceName%
	timeout /t 10 >nul
)

REM Check for abnormal .md5Cache file
:checkMD5
set md5Path=%servicePath%\.md5Cache
if exist "%md5Path%" (
    REM Get the file size in bytes
    for %%A in ("%md5Path%") do set fileSize=%%~zA

    REM Check if the file size is larger than 5120 bytes (5KB)
    if !fileSize! GTR 5120 (
        REM Check if the file contains the \u0000 character
        findstr /R /C:"\x00" "%md5Path%" >nul
        if %errorlevel%==0 (
            REM Remove the file
            del "%md5Path%" /Q
            if %errorlevel%==0 (
                echo [7m INFO [0m: Illegal \u0000 characters found. File .md5Cache deleted successfully.
            ) else (
                echo [103;90m WARN [0m: Error deleting file .md5Cache Please remove manually before proceeding:
				echo [103;90m WARN [0m: Remove: %servicePath%\.md5Cache
				echo [103;90m WARN [0m: Press ANY key to continue the script...
				choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
            )
        )
    )
)

:startService
echo [7m INFO [0m: Starting %serviceName% service...
timeout /t 5 >nul
sc start %serviceName%
timeout /t 1 >nul
sc query %serviceName% | find "RUNNING" >nul
if %errorlevel%==0 (
	echo [7m INFO [0m: %serviceName% started successfully.
) else (
	set /a restarts+=1
	if %restarts% lss 4 (
		echo [7m INFO [0m: Attempt %restarts% to start %serviceName% failed. Retrying...
		goto startService
	) else (
		echo [103;90m WARN [0m: Failed to start %serviceName% after 3 attempts.
		set brokenConfigs=TRUE
		REM goto replaceConfigs
	)
)

REM Check if service is running for 3 times
echo [7m INFO [0m: Checking if the %serviceName% is running...
:checkState
sc query %serviceName% | find "RUNNING" >nul
if %errorlevel% == 0 (
    if %checks% lss 4 (
		echo [7m INFO [0m: Checked %checks% time(s^) %serviceName% is running.
		timeout /t 3 >nul
		set /a checks+=1
		goto checkState
	) else (
		echo [7;92m SUCCESS [0m: %serviceName% started successfully and is running normally.
	)
) else (
	if %restarts% lss 4 (
		echo [103;90m WARN [0m: %serviceName% is not running. Attempting to start the service...
		goto startService
	)
	echo [101;93m FATAL [0m: Repair Failed. Possibly broken core files. Please reinstall FileCatalyst Hotfolder.
)

:cleanFlag
REM Remove flagFile
attrib -h "%flagFile%"
del /Q "%flagFile%" >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [103;90m WARN [0m: Failed to delete flagFile inside %tempPath%.
)

:-------------------------------------

choice /t 10 /d Y /m "Press key to continue or wait 10 seconds ..." 2>nul
endlocal