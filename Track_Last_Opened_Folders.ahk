; Explorer Window History Tracker with GUI
; Tracks last 20 closed Explorer windows and allows reopening
#Persistent
#SingleInstance Force
#NoEnv
SetBatchLines -1

global closedHistory := []
global MAX_HISTORY := 20
global hGui := 0
global hListView := 0

; Register for shell window events
DllCall("RegisterShellHookWindow", "UInt", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "Str", "SHELLHOOK"), "ShellEvent")

; Also track via polling as backup
SetTimer, TrackWindows, 2000
global previousWindows := {}

; Hotkey to show GUI
^+h::ShowHistoryGUI()

return

; ==================== Window Tracking ====================

TrackWindows:
    windows := ComObjCreate("Shell.Application").Windows
    current := {}

    Loop % windows.Count
    {
        try {
            window := windows.Item(A_Index - 1)
            if (window.Document && window.Document.Folder) {
                hwnd := window.HWND
                path := window.Document.Folder.Self.Path
                current[hwnd] := path
            }
        }
    }

    ; Check for closed windows
    for hwnd, path in previousWindows {
        if !current.HasKey(hwnd) {
            AddToHistory(path)
        }
    }

    previousWindows := current
return

; Handle shell hook events
ShellEvent(wParam, lParam) {
    Critical
    ; HSHELL_WINDOWDESTROYED = 2
    if (wParam = 2) {
        hwnd := lParam
        WinGetClass, class, ahk_id %hwnd%
        if (class = "CabinetWClass" || class = "ExploreWClass") {
            ; Try to get the path before window is fully destroyed
            try {
                windows := ComObjCreate("Shell.Application").Windows
                Loop % windows.Count {
                    window := windows.Item(A_Index - 1)
                    if (window.HWND = hwnd && window.Document && window.Document.Folder) {
                        path := window.Document.Folder.Self.Path
                        AddToHistory(path)
                        break
                    }
                }
            }
        }
    }
}

AddToHistory(path) {
    if (path = "" || !FileExist(path))
        return
    
    ; Remove duplicates from history
    Loop % closedHistory.Length() {
        if (closedHistory[A_Index].path = path) {
            closedHistory.RemoveAt(A_Index)
            break
        }
    }
    
    ; Add to beginning of array with timestamp
    FormatTime, timeStamp, , HH:mm
    entry := {path: path, time: timeStamp}
    closedHistory.InsertAt(1, entry)
    
    ; Keep only last 20
    if (closedHistory.Length() > MAX_HISTORY) {
        closedHistory.RemoveAt(MAX_HISTORY + 1)
    }
    
    ; Update GUI if it's open
    if (hGui && WinExist("ahk_id" hGui))
        UpdateListView()
}

; ==================== GUI Functions ====================

ShowHistoryGUI() {
    global hGui, hListView, closedHistory
    
    if (hGui && WinExist("ahk_id" hGui)) {
        Gui, Destroy
    }
    
    ; Dark theme colors
    bgColor := "0x1E1E1E"
    textColor := "0xD4D4D4"
    buttonColor := "0x2D2D30"
    
    Gui, +HwndHGui +AlwaysOnTop +Resize
    Gui, Color, %bgColor%
    Gui, Font, s9 c%textColor%, Segoe UI
	
	; ListView with dark styling - no header, no checkboxes, hide selection
    Gui, Add, ListView, x10 y10 w760 h400 HwndhListView Background1E1E1E cWhite -E0x200 gListViewEvent, Time|Item|Path
    
    ; Buttons with dark styling
    Gui, Font, s10 cWhite, Segoe UI
    Gui, Add, Button, x10 y420 w120 h35 gReopenSelected HwndHBtn1, Reopen Selected
    Gui, Add, Button, x140 y420 w120 h35 gClearHistory HwndHBtn2, Clear History
    Gui, Add, Button, x650 y420 w120 h35 gCloseGUI HwndHBtn3, Close
    
    ; Apply dark button styling
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn3, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Populate ListView
    UpdateListView()
    
    Gui, Show, w780 h465, Explorer History
}

UpdateListView() {
    global hListView, closedHistory
    
    if (!hListView)
        return
    
    GuiControl, -Redraw, %hListView%
    LV_Delete()
    
    if (closedHistory.Length() = 0) {
        LV_Add("", "", "No History", "")
    } else {
        Loop % closedHistory.Length() {
            entry := closedHistory[A_Index]
            timeStr := entry.time
            itemNum := "Item " . A_Index
            path := entry.path
            
            LV_Add("", timeStr, itemNum, path)
        }
    }
    
    ; Auto-size columns
    LV_ModifyCol(1, 60)   ; Time column
    LV_ModifyCol(2, 60)   ; Item number column
    LV_ModifyCol(3, 630)  ; Path column
    
    GuiControl, +Redraw, %hListView%
}

ListViewEvent:
    if (A_GuiEvent = "DoubleClick") {
        RowNumber := LV_GetNext(0)
        if (RowNumber > 0) {
            LV_GetText(path, RowNumber, 3)
            if (path != "" && path != "No History") {
                ReopenFolder(path)
            }
        }
    }
return

GuiSize:
    if (A_EventInfo != 1) {  ; Not minimized
        newWidth := A_GuiWidth - 20
        newHeight := A_GuiHeight - 75
        GuiControl, Move, %hListView%, w%newWidth% h%newHeight%
        
        ; Reposition buttons
        buttonY := A_GuiHeight - 45
        GuiControl, Move, Button1, y%buttonY%
        GuiControl, Move, Button2, y%buttonY%
        closeX := A_GuiWidth - 130
        GuiControl, Move, Button3, x%closeX% y%buttonY%
        
        ; Resize columns on window resize
        newCol3Width := newWidth - 130
        LV_ModifyCol(3, newCol3Width)
    }
return

ReopenSelected:
    global closedHistory
    
    RowNumber := 0
    pathsToOpen := []
    
    ; Collect all selected rows
    Loop {
        RowNumber := LV_GetNext(RowNumber)
        if (!RowNumber)
            break
        
        LV_GetText(path, RowNumber, 3)
        if (path != "" && path != "No History")
            pathsToOpen.Push(path)
    }
    
    ; Open all selected folders
    for index, path in pathsToOpen {
        ReopenFolder(path)
    }
    
    if (pathsToOpen.Length() = 0) {
        MsgBox, 48, Explorer History, Please select one or more folders to reopen.
    }
return

ReopenFolder(path) {
    if (FileExist(path)) {
        try {
            shell := ComObjCreate("Shell.Application")
            shell.Open(path)
        } catch e {
            MsgBox, 16, Error, Failed to open: %path%
        }
    } else {
        MsgBox, 16, Path Not Found, The folder no longer exists:`n%path%
    }
}

ClearHistory:
    global hGui
    ; Make message box appear in front
    Gui, +OwnDialogs
    MsgBox, 36, Clear History, Are you sure you want to clear the entire history?
    IfMsgBox, Yes
    {
        closedHistory := []
        UpdateListView()
    }
return


CloseGUI:
GuiClose:
GuiEscape:
    Gui, Destroy
    hGui := 0
    hListView := 0
return