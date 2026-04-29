on waitForProcess(processName, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      if exists process processName then return true
    end tell
    delay 0.5
  end repeat
  return false
end waitForProcess

on waitForMenuBarExtra(processName, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      tell process processName
        if (count of menu bar items of menu bar 2) > 0 then return true
      end tell
    end tell
    delay 0.5
  end repeat
  return false
end waitForMenuBarExtra

set appName to "PlaywrightDashboard"
set appPath to POSIX path of (path to me)
set scriptPath to do shell script "dirname " & quoted form of appPath
set repoPath to do shell script "cd " & quoted form of scriptPath & "/.. && pwd"
set bundlePath to repoPath & "/dist/PlaywrightDashboard.app"

do shell script "open " & quoted form of bundlePath

if not waitForProcess(appName, 20) then error "PlaywrightDashboard process did not launch"

if not waitForMenuBarExtra(appName, 20) then error "PlaywrightDashboard menu bar extra did not appear"

tell application appName to quit
