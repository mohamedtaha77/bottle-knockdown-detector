@echo off
cd /d "C:\Users\Mohammed Taha\DSAI 352 - CV - Bonus Project - SPR 26 - Mohammed Taha - 202201788\bottle_knockdown_app"
"C:\src\flutter\bin\flutter.bat" build apk --debug > fl-build.txt 2>&1
echo EXIT_CODE:%ERRORLEVEL% >> fl-build.txt
