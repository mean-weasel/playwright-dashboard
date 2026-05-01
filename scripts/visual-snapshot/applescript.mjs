export function waitForWindowScript(expectedElement) {
  return `
on waitForElement(processName, elementName, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      if exists process processName then
        tell process processName
          if (count of windows) > 0 then
            set allItems to entire contents of window 1
            repeat with itemRef in allItems
              try
                if (name of itemRef as string) is elementName then return true
              end try
              try
                if (value of attribute "AXIdentifier" of itemRef as string) is elementName then return true
              end try
            end repeat
          end if
        end tell
      end if
    end tell
    delay 0.5
  end repeat
  return false
end waitForElement

set appName to "PlaywrightDashboard"
if not waitForElement(appName, "${expectedElement}", 80) then error "Timed out waiting for ${expectedElement}"
`;
}

export function structuralSnapshotScript() {
  return `
set appName to "PlaywrightDashboard"
set output to ""
tell application "System Events"
  if not (exists process appName) then return "windowCount=0" & linefeed
  tell process appName
    set output to output & "windowCount=" & (count of windows) & linefeed
    if (count of windows) > 0 then
      set allItems to entire contents of window 1
      set output to output & "itemCount=" & (count of allItems) & linefeed
      repeat with itemRef in allItems
        set roleText to ""
        set nameText to ""
        set idText to ""
        try
          set roleText to role of itemRef as string
        end try
        try
          set nameText to name of itemRef as string
        end try
        try
          set idText to value of attribute "AXIdentifier" of itemRef as string
        end try
        if roleText is not "" or nameText is not "" or idText is not "" then
          set output to output & "item" & tab & roleText & tab & nameText & tab & idText & linefeed
        end if
      end repeat
    end if
  end tell
end tell
return output
`;
}

export function waitForAppWindowScript() {
  return `
set appName to "PlaywrightDashboard"
repeat with attempt from 1 to 80
  tell application "System Events"
    if exists process appName then
      tell process appName
        if (count of windows) > 0 then return true
      end tell
    end if
  end tell
  delay 0.5
end repeat
error "Timed out waiting for PlaywrightDashboard window"
`;
}

export function windowRectScript() {
  return `
set appName to "PlaywrightDashboard"
tell application "System Events"
  tell process appName
    set frontmost to true
    set windowPosition to position of window 1
    set windowSize to size of window 1
  end tell
end tell
return "x=" & (item 1 of windowPosition as integer) & " y=" & (item 2 of windowPosition as integer) & " w=" & (item 1 of windowSize as integer) & " h=" & (item 2 of windowSize as integer)
`;
}

export function uiSnapshotScript() {
  return `
set appName to "PlaywrightDashboard"
set output to ""
tell application "System Events"
  if exists process appName then
    tell process appName
      set output to output & "windows=" & (count of windows) & linefeed
      if (count of windows) > 0 then
        set allItems to entire contents of window 1
        repeat with itemRef in allItems
          try
            set roleText to role of itemRef as string
            set nameText to "missing"
            try
              set nameText to name of itemRef as string
            end try
            set idText to ""
            try
              set idText to value of attribute "AXIdentifier" of itemRef as string
            end try
            set output to output & roleText & " name=" & nameText & " id=" & idText & linefeed
          end try
        end repeat
      end if
    end tell
  end if
end tell
return output
`;
}
