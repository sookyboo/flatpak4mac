on run
    try
        set actionItems to {"Open Discover", "Switch to XFCE Desktop", "Switch to KDE Plasma", "Switch to RetroDECK", "Install Discover", "List installed Flatpaks", "Update Flatpaks", "Launch a Flatpak", "Start VM", "Stop VM", "Check connection"}
        set actionChoice to choose from list actionItems with title "Flatpak Manager" with prompt "Choose an action:" default items {"Open Discover"} without multiple selections allowed
        if actionChoice is false then return
        set backendChoice to choose from list {"Krunkit (Lima)", "UTM"} with title "Flatpak Manager" with prompt "Which Linux VM backend?" default items {"UTM"} without multiple selections allowed
        if backendChoice is false then return
        set backendID to "krunkit"
        if item 1 of backendChoice is "UTM" then set backendID to "utm"
        set selectedAction to item 1 of actionChoice
        set commandID to "discover"
        if selectedAction is "Switch to XFCE Desktop" then set commandID to "session"
        if selectedAction is "Switch to KDE Plasma" then set commandID to "session"
        if selectedAction is "Switch to RetroDECK" then set commandID to "session"
        if selectedAction is "Install Discover" then set commandID to "setup"
        if selectedAction is "List installed Flatpaks" then set commandID to "list"
        if selectedAction is "Update Flatpaks" then set commandID to "update"
        if selectedAction is "Start VM" then set commandID to "start"
        if selectedAction is "Stop VM" then set commandID to "stop"
        if selectedAction is "Check connection" then set commandID to "check"
        set extraArg to ""
        if commandID is "session" then
            set confirmation to display dialog "Switching sessions closes the applications currently displayed in the UTM VM. Continue?" buttons {"Cancel", "Switch"} default button "Cancel" with title "Flatpak Manager"
            if button returned of confirmation is not "Switch" then return
            if selectedAction is "Switch to XFCE Desktop" then set extraArg to " xfce"
            if selectedAction is "Switch to KDE Plasma" then set extraArg to " plasma"
            if selectedAction is "Switch to RetroDECK" then set extraArg to " retrodeck"
        end if
        if selectedAction is "Launch a Flatpak" then
            set commandID to "launch"
            set d to display dialog "Flatpak application ID (for example org.xfce.mousepad):" default answer "org.xfce.mousepad" with title "Launch Flatpak"
            set extraArg to " " & quoted form of (text returned of d)
        end if
        set modeFlags to ""
        if commandID is "launch" or commandID is "discover" then
            set modeChoice to choose from list {"Automatic (saved preference)", "macOS windows (XQuartz)", "Linux VM display (GPU if available)"} with title "Flatpak Manager" with prompt "How should this application appear?" default items {"Automatic (saved preference)"} without multiple selections allowed
            if modeChoice is false then return
            set modeID to "auto"
            if item 1 of modeChoice is "macOS windows (XQuartz)" then set modeID to "macos"
            if item 1 of modeChoice is "Linux VM display (GPU if available)" then set modeID to "gpu"
            set modeFlags to " --mode " & quoted form of modeID
            if modeID is not "auto" then
                set rememberAnswer to display dialog "Remember this display mode for this application and backend?" buttons {"No", "Yes"} default button "No" with title "Flatpak Manager"
                if button returned of rememberAnswer is "Yes" then set modeFlags to modeFlags & " --remember"
            end if
        end if
        set scriptPath to POSIX path of (path to resource "flatpak4mac-host.sh" in bundle (path to me))
        set shellCommand to quoted form of scriptPath & " --backend " & quoted form of backendID & modeFlags & " " & quoted form of commandID & extraArg
        tell application "Terminal"
            activate
            do script shellCommand
        end tell
    on error errorMessage number errorNumber
        if errorNumber is not -128 then display alert "Flatpak Manager" message errorMessage as warning
    end try
end run
