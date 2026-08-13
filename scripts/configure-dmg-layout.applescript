on run arguments
    if (count of arguments) is not 3 then
        error "Expected mount path, app name, and Applications link name"
    end if

    set mountPath to item 1 of arguments
    set appName to item 2 of arguments
    set applicationsLinkName to item 3 of arguments
    set volumeFolder to POSIX file mountPath as alias

    tell application "Finder"
        open volumeFolder
        set diskWindow to container window of volumeFolder
        set current view of diskWindow to icon view
        set toolbar visible of diskWindow to false
        set statusbar visible of diskWindow to false
        set bounds of diskWindow to {120, 120, 680, 440}

        set iconOptions to icon view options of diskWindow
        set arrangement of iconOptions to not arranged
        set icon size of iconOptions to 104
        set text size of iconOptions to 13
        set shows item info of iconOptions to false
        set shows icon preview of iconOptions to true
        set label position of iconOptions to bottom

        set position of item appName of volumeFolder to {155, 150}
        set position of item applicationsLinkName of volumeFolder to {405, 150}

        update volumeFolder without registering applications
        delay 1
        close diskWindow
    end tell
end run
