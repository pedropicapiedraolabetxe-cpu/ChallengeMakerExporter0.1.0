// Challenge Maker Exporter
// Windows-only companion for the Binding of Isaac Challenge Maker mod.
// Uses only the Go standard library and Win32 APIs.
package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	appTitle = "Challenge Maker Exporter 0.8.105"

	WS_OVERLAPPEDWINDOW = 0x00CF0000
	WS_VISIBLE          = 0x10000000
	WS_CHILD            = 0x40000000
	WS_BORDER           = 0x00800000
	WS_VSCROLL          = 0x00200000
	WS_TABSTOP          = 0x00010000

	BS_PUSHBUTTON = 0x00000000

	LBS_NOTIFY           = 0x0001
	LBS_MULTIPLESEL      = 0x0008
	LBS_NOINTEGRALHEIGHT = 0x0100

	WM_CREATE  = 0x0001
	WM_DESTROY = 0x0002
	WM_COMMAND = 0x0111
	WM_SETFONT = 0x0030

	SW_SHOWDEFAULT = 10
	SW_HIDE        = 0
	SW_SHOW        = 5
	CW_USEDEFAULT  = ^uint32(0x7fffffff)

	LB_ADDSTRING = 0x0180
	LB_GETSEL    = 0x0187
	LB_SETSEL    = 0x0185
	LB_GETCOUNT  = 0x018B

	LBN_SELCHANGE = 1

	ID_SELECT_ALL = 1001
	ID_EXPORT     = 1002
	ID_LIST       = 1003
	ID_STATUS     = 1004
	ID_PATH       = 1005
	ID_FOLDER_OK  = 1006
	ID_FOLDER_NO  = 1007

	MB_OK          = 0x00000000
	MB_ICONERROR   = 0x00000010
	MB_ICONINFO    = 0x00000040
	MB_ICONWARNING = 0x00000030

	COLOR_WINDOW     = 5
	IDC_ARROW        = 32512
	DEFAULT_GUI_FONT = 17
)

type WNDCLASSEX struct {
	CbSize        uint32
	Style         uint32
	LpfnWndProc   uintptr
	CbClsExtra    int32
	CbWndExtra    int32
	HInstance     syscall.Handle
	HIcon         syscall.Handle
	HCursor       syscall.Handle
	HbrBackground syscall.Handle
	LpszMenuName  *uint16
	LpszClassName *uint16
	HIconSm       syscall.Handle
}

type POINT struct{ X, Y int32 }
type MSG struct {
	HWnd    syscall.Handle
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      POINT
}

type Challenge struct {
	Description        string               `json:"description"`
	Conditions         json.RawMessage      `json:"conditions"`
	ID                 string               `json:"id"`
	Title              string               `json:"title"`
	PlayerType         int                  `json:"playerType"`
	PlayerName         string               `json:"playerName"`
	PlayerIsModded     bool                 `json:"playerIsModded"`
	PlayerToken        string               `json:"playerToken"`
	FinalBossKey       string               `json:"finalBossKey"`
	FinalBossName      string               `json:"finalBossName"`
	FinalBossID        int                  `json:"finalBossID"`
	Ending             int                  `json:"ending"`
	EndStage           int                  `json:"endStage"`
	AltPath            *bool                `json:"altPath"`
	MegaSatan          bool                 `json:"megaSatan"`
	SecretPath         bool                 `json:"secretPath"`
	Difficulty         int                  `json:"difficulty"`
	StartingItems      []int                `json:"startingItems"`
	StartingItemTokens []string             `json:"startingItemTokens"`
	StartingPickups    []PickupRule         `json:"startingPickups"`
	StartStats         FlexibleFloatMap     `json:"startStats"`
	StartHealth        FlexibleIntMap       `json:"startHealth"`
	StartCharges       FlexibleIntMap       `json:"startCharges"`
	StartCoins         *int                 `json:"startCoins"`
	StartBombs         *int                 `json:"startBombs"`
	StartKeys          *int                 `json:"startKeys"`
	CurseModes         FlexibleStringMap    `json:"curseModes"`
	BannedPickups      []PickupRule         `json:"bannedPickups"`
	BannedItems        []int                `json:"bannedItems"`
	BannedPools        []BannedPool         `json:"bannedPools"`
	BannedItemTokens   []string             `json:"bannedItemTokens"`
	BannedRooms        []int                `json:"bannedRooms"`
	BannedRoomNames    []string             `json:"bannedRoomNames"`
	Blindfold          bool                 `json:"blindfold"`
	NoSoul             bool                 `json:"noSoul"`
	Transformations    []TransformationRule `json:"transformations"`
}

// Isaac's JSON encoder serializes an empty Lua table as [] rather than {}.
// Both forms must load without discarding every challenge in the save slot.
type FlexibleFloatMap map[string]float64
type FlexibleIntMap map[string]int
type FlexibleStringMap map[string]string

func emptyLuaTable(data []byte) bool {
	s := strings.TrimSpace(string(data))
	return s == "null" || (strings.HasPrefix(s, "[") && strings.HasSuffix(s, "]") && strings.TrimSpace(s[1:len(s)-1]) == "")
}

func (m *FlexibleFloatMap) UnmarshalJSON(data []byte) error {
	if emptyLuaTable(data) {
		*m = FlexibleFloatMap{}
		return nil
	}
	return json.Unmarshal(data, (*map[string]float64)(m))
}

func (m *FlexibleIntMap) UnmarshalJSON(data []byte) error {
	if emptyLuaTable(data) {
		*m = FlexibleIntMap{}
		return nil
	}
	return json.Unmarshal(data, (*map[string]int)(m))
}

func (m *FlexibleStringMap) UnmarshalJSON(data []byte) error {
	if emptyLuaTable(data) {
		*m = FlexibleStringMap{}
		return nil
	}
	return json.Unmarshal(data, (*map[string]string)(m))
}

type TransformationRule struct {
	ID      int    `json:"id"`
	Key     string `json:"key"`
	Name    string `json:"name"`
	Special string `json:"special"`
}

type BannedPool struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Label string `json:"label"`
}

type PickupRule struct {
	Kind     string `json:"kind"`
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Token    string `json:"token"`
	Delivery string `json:"delivery"`
}

// Must match the in-game editor. Progression-critical room types that older
// Challenge Maker versions exposed are deliberately ignored during export.
var bannableRoomTypes = map[int]bool{
	2: true, 4: true, 6: true, 7: true, 8: true, 9: true, 10: true,
	11: true, 12: true, 13: true, 14: true, 15: true, 16: true,
	18: true, 19: true, 20: true, 21: true, 22: true, 24: true, 29: true,
}

func filteredBannedRooms(rooms []int) []int {
	out := make([]int, 0, len(rooms))
	seen := map[int]bool{}
	for _, id := range rooms {
		if bannableRoomTypes[id] && !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}

//go:embed cm_description.lua
var descriptionLua string

//go:embed cm_general.lua
var generalLua string

//go:embed cm_bans.lua
var banRulesLua string

//go:embed cm_conditions.lua
var conditionsLua string

//go:embed cm_rewards.lua
var rewardsLua string

//go:embed conditions_export_adapter.lua
var conditionsAdapterLua string

type SaveStore struct {
	ChallengeMakerVersion int         `json:"challengeMakerVersion"`
	Challenges            []Challenge `json:"challenges"`
}

type challengeWithSource struct {
	Challenge
	ModTime time.Time
	Slot    string
}

var readWarnings []string

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")

	procRegisterClassExW = user32.NewProc("RegisterClassExW")
	procCreateWindowExW  = user32.NewProc("CreateWindowExW")
	procDefWindowProcW   = user32.NewProc("DefWindowProcW")
	procShowWindow       = user32.NewProc("ShowWindow")
	procUpdateWindow     = user32.NewProc("UpdateWindow")
	procGetMessageW      = user32.NewProc("GetMessageW")
	procTranslateMessage = user32.NewProc("TranslateMessage")
	procDispatchMessageW = user32.NewProc("DispatchMessageW")
	procPostQuitMessage  = user32.NewProc("PostQuitMessage")
	procSendMessageW     = user32.NewProc("SendMessageW")
	procSetWindowTextW   = user32.NewProc("SetWindowTextW")
	procMessageBoxW      = user32.NewProc("MessageBoxW")
	procLoadCursorW      = user32.NewProc("LoadCursorW")
	procEnableWindow     = user32.NewProc("EnableWindow")

	procGetModuleHandleW = kernel32.NewProc("GetModuleHandleW")
	procGetStockObject   = gdi32.NewProc("GetStockObject")

	hMain, hList, hStatus, hPath, hExport, hSelect, hHint syscall.Handle
	hFolderLabel, hFolderEdit, hFolderOK, hFolderCancel   syscall.Handle
	guiFont                                               uintptr
	isaacDir                                              string
	challenges                                            []Challenge
)

func utf16Ptr(s string) *uint16 { return syscall.StringToUTF16Ptr(s) }
func loword(v uintptr) uint16   { return uint16(v & 0xffff) }
func hiword(v uintptr) uint16   { return uint16((v >> 16) & 0xffff) }

func sendMessage(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	r, _, _ := procSendMessageW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func setText(hwnd syscall.Handle, s string) {
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(utf16Ptr(s))))
}

func messageBox(title, text string, flags uintptr) {
	procMessageBoxW.Call(uintptr(hMain), uintptr(unsafe.Pointer(utf16Ptr(text))), uintptr(unsafe.Pointer(utf16Ptr(title))), flags)
}

func createControl(className, text string, style uint32, x, y, w, h int32, parent syscall.Handle, id int) syscall.Handle {
	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(utf16Ptr(className))),
		uintptr(unsafe.Pointer(utf16Ptr(text))),
		uintptr(style),
		uintptr(x), uintptr(y), uintptr(w), uintptr(h),
		uintptr(parent), uintptr(id), 0, 0,
	)
	handle := syscall.Handle(hwnd)
	if guiFont != 0 {
		sendMessage(handle, WM_SETFONT, guiFont, 1)
	}
	return handle
}

func wndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		hSelect = createControl("BUTTON", "SELECT ALL", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON, 26, 24, 140, 38, hwnd, ID_SELECT_ALL)
		hExport = createControl("BUTTON", "EXPORT", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON, 444, 24, 140, 38, hwnd, ID_EXPORT)
		hHint = createControl("STATIC", "Click challenge names to select/deselect them", WS_CHILD|WS_VISIBLE, 176, 31, 258, 24, hwnd, 0)
		hList = createControl("LISTBOX", "", WS_CHILD|WS_VISIBLE|WS_BORDER|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_MULTIPLESEL|LBS_NOINTEGRALHEIGHT, 26, 82, 558, 310, hwnd, ID_LIST)
		hStatus = createControl("STATIC", "", WS_CHILD|WS_VISIBLE, 26, 406, 558, 24, hwnd, ID_STATUS)
		hPath = createControl("STATIC", "", WS_CHILD|WS_VISIBLE, 26, 432, 558, 36, hwnd, ID_PATH)
		hFolderLabel = createControl("STATIC", "Pack folder inside mods:", WS_CHILD, 74, 157, 462, 24, hwnd, 0)
		hFolderEdit = createControl("EDIT", lastExportFolder, WS_CHILD|WS_BORDER|WS_TABSTOP|0x80, 74, 187, 462, 30, hwnd, 0)
		hFolderOK = createControl("BUTTON", "EXPORT", WS_CHILD|WS_TABSTOP|1, 302, 236, 110, 34, hwnd, ID_FOLDER_OK)
		hFolderCancel = createControl("BUTTON", "CANCEL", WS_CHILD|WS_TABSTOP, 426, 236, 110, 34, hwnd, ID_FOLDER_NO)
		sendMessage(hFolderEdit, 0x00C5, 80, 0)
		populateList()
		updateStatus()
		if len(challenges) == 0 {
			procEnableWindow.Call(uintptr(hExport), 0)
		}
		if len(readWarnings) > 0 {
			messageBox(appTitle, "Some saved data could not be read. Valid challenges are still listed.\n\n"+strings.Join(readWarnings, "\n\n"), MB_OK|MB_ICONWARNING)
		}
		return 0

	case WM_COMMAND:
		id := int(loword(wParam))
		code := hiword(wParam)
		switch id {
		case ID_SELECT_ALL:
			if len(challenges) > 0 {
				sendMessage(hList, LB_SETSEL, 1, ^uintptr(0))
				updateStatus()
			}
			return 0
		case ID_EXPORT:
			exportSelected()
			return 0
		case ID_FOLDER_NO:
			closeFolderPrompt()
			return 0
		case ID_FOLDER_OK:
			confirmFolderPrompt()
			return 0
		case ID_LIST:
			if code == LBN_SELCHANGE {
				updateStatus()
			}
		}

	case WM_DESTROY:
		procPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func selectedIndices() []int {
	var out []int
	for i := range challenges {
		if sendMessage(hList, LB_GETSEL, uintptr(i), 0) != 0 {
			out = append(out, i)
		}
	}
	return out
}

func updateStatus() {
	n := len(selectedIndices())
	if len(challenges) == 0 {
		if len(readWarnings) > 0 {
			setText(hStatus, "Saved data could not be read. See the error message for the file and cause.")
		} else {
			setText(hStatus, "No saved challenges found. Create one in Isaac with F3 -> CREATE CHALLENGE.")
		}
	} else {
		setText(hStatus, fmt.Sprintf("%d of %d challenge(s) selected", n, len(challenges)))
	}
	if isaacDir != "" {
		setText(hPath, "Isaac: "+isaacDir)
	} else {
		setText(hPath, "Isaac installation not found automatically.")
	}
}

func populateList() {
	for _, c := range challenges {
		sendMessage(hList, LB_ADDSTRING, 0, uintptr(unsafe.Pointer(utf16Ptr(c.Title))))
	}
}

var lastExportFolder = "My Challenges"

func validExportFolder(name string) bool {
	if name == "" || len([]rune(name)) > 80 || strings.TrimSpace(name) != name || strings.HasSuffix(name, ".") {
		return false
	}
	for _, r := range name {
		if r < 32 || strings.ContainsRune("<>:\"/\\|?*", r) {
			return false
		}
	}
	base := strings.ToUpper(strings.SplitN(name, ".", 2)[0])
	if base == "." || base == ".." || base == "CON" || base == "PRN" || base == "AUX" || base == "NUL" {
		return false
	}
	if len(base) == 4 && (strings.HasPrefix(base, "COM") || strings.HasPrefix(base, "LPT")) && base[3] >= '0' && base[3] <= '9' {
		return false
	}
	return true
}

func closeFolderPrompt() {
	for _, h := range []syscall.Handle{hFolderLabel, hFolderEdit, hFolderOK, hFolderCancel} {
		procShowWindow.Call(uintptr(h), SW_HIDE)
	}
	for _, h := range []syscall.Handle{hSelect, hExport, hHint, hList, hStatus, hPath} {
		procShowWindow.Call(uintptr(h), SW_SHOW)
	}
	if len(challenges) == 0 {
		procEnableWindow.Call(uintptr(hExport), 0)
	}
	user32.NewProc("SetFocus").Call(uintptr(hList))
}

func confirmFolderPrompt() {
	var text [256]uint16
	user32.NewProc("GetWindowTextW").Call(uintptr(hFolderEdit), uintptr(unsafe.Pointer(&text[0])), uintptr(len(text)))
	name := syscall.UTF16ToString(text[:])
	if !validExportFolder(name) {
		messageBox(appTitle, "Enter a folder name (1-80 characters). Do not use paths, reserved names, or trailing spaces/dots.", MB_OK|MB_ICONWARNING)
		return
	}
	lastExportFolder = name
	closeFolderPrompt()
	exportSelectedToFolder(name)
}

func exportSelected() {
	if len(selectedIndices()) == 0 {
		messageBox(appTitle, "Select at least one challenge first.", MB_OK|MB_ICONWARNING)
		return
	}
	for _, h := range []syscall.Handle{hSelect, hExport, hHint, hList, hStatus, hPath} {
		procShowWindow.Call(uintptr(h), SW_HIDE)
	}
	setText(hFolderEdit, lastExportFolder)
	for _, h := range []syscall.Handle{hFolderLabel, hFolderEdit, hFolderOK, hFolderCancel} {
		procShowWindow.Call(uintptr(h), SW_SHOW)
	}
	user32.NewProc("SetFocus").Call(uintptr(hFolderEdit))
	sendMessage(hFolderEdit, 0x00B1, 0, ^uintptr(0))
}

// Each pack is a complete, independent Isaac mod. Never rewrite other mods.
func prepareFolderExport(modsDir, folder string, selected, saved []Challenge) (map[string]string, int, error) {
	if !validExportFolder(folder) {
		return nil, 0, fmt.Errorf("invalid folder name")
	}
	// Windows paths are case insensitive, including when tests run on Linux.
	dirs, err := os.ReadDir(modsDir)
	if err != nil && !os.IsNotExist(err) {
		return nil, 0, err
	}
	for _, entry := range dirs {
		if strings.EqualFold(entry.Name(), folder) {
			folder = entry.Name()
			break
		}
	}
	outDir := filepath.Join(modsDir, folder)
	marker := filepath.Join(outDir, "cm_pack.json")
	if info, err := os.Stat(outDir); err == nil {
		if !info.IsDir() {
			return nil, 0, fmt.Errorf("destination is not a folder")
		}
		raw, err := os.ReadFile(marker)
		var owner struct {
			Format string `json:"format"`
		}
		if err != nil || json.Unmarshal(raw, &owner) != nil || owner.Format != "challenge-maker-pack-v1" {
			return nil, 0, fmt.Errorf("Folder '%s' already exists and is not an independent Challenge Maker pack. Choose another name to avoid overwriting a mod", folder)
		}
	} else if !os.IsNotExist(err) {
		return nil, 0, err
	}
	identity := fmt.Sprintf("cm_pack_%x", sha256.Sum256([]byte(strings.ToLower(folder))))
	moduleDir := "scripts/" + identity
	configs := append([]Challenge(nil), selected...)
	used := map[string]bool{}
	for i := range configs {
		title := strings.TrimSpace(configs[i].Title)
		if title == "" {
			title = "Generated Challenge"
		}
		base := title + " [" + folder + "]"
		title = base
		for n := 2; used[title]; n++ {
			title = fmt.Sprintf("%s (%d)", base, n)
		}
		used[title] = true
		configs[i].Title = title
		if len(configs[i].Conditions) > 0 && !json.Valid(configs[i].Conditions) {
			return nil, 0, fmt.Errorf("invalid conditions for %s", title)
		}
	}
	raw, err := json.MarshalIndent(selected, "", "  ")
	if err != nil {
		return nil, 0, err
	}
	main := buildGeneratedLua(configs)
	main += "\ninclude(" + luaQuote(moduleDir+"/cm_description") + ").Attach(mod, currentConfig)\n"
	main = strings.Replace(main, `RegisterMod("Challenge Maker Exported", 1)`, "RegisterMod("+luaQuote(identity)+", 1)", 1)
	main = strings.ReplaceAll(main, `include("cm_bans")`, "include("+luaQuote(moduleDir+"/cm_bans")+")")
	main = strings.ReplaceAll(main, `include("cm_general")`, "include("+luaQuote(moduleDir+"/cm_general")+")")
	main = strings.ReplaceAll(main, `include('cm_conditions')`, "include("+luaQuote(moduleDir+"/cm_conditions")+")")
	conditions := strings.ReplaceAll(conditionsLua, `include("cm_rewards")`, "include("+luaQuote(moduleDir+"/cm_rewards")+")")
	files := map[string]string{
		filepath.Join(outDir, moduleDir, "cm_description.lua"): descriptionLua,
		filepath.Join(outDir, moduleDir, "cm_general.lua"):     generalLua,
		filepath.Join(outDir, "main.lua"):                      main,
		filepath.Join(outDir, "content", "challenges.xml"):     buildChallengesXML(configs),
		filepath.Join(outDir, "challenges.json"):               string(raw),
		filepath.Join(outDir, moduleDir, "cm_conditions.lua"):  conditions,
		filepath.Join(outDir, moduleDir, "cm_rewards.lua"):     rewardsLua,
		filepath.Join(outDir, moduleDir, "cm_bans.lua"):        banRulesLua,
		marker:                                `{"format":"challenge-maker-pack-v1"}`,
		filepath.Join(outDir, "metadata.xml"): "<metadata>\n<name>" + xmlEscape(folder) + "</name>\n<directory>" + xmlEscape(folder) + "</directory>\n<id></id>\n<description>Independent Challenge Maker pack.</description>\n<version>1.0</version>\n</metadata>\n",
		filepath.Join(outDir, "README.txt"):   "Independent Challenge Maker pack. Enable this mod and restart Isaac.\r\nChallenge Maker and the old challenge_maker_exported mod are not required.\r\nREPENTOGON and content mods referenced by your challenges are still required.\r\nKeep the whole pack folder together, including scripts. Re-export to update it.\r\n",
	}
	return files, len(configs), nil
}

func exportSelectedToFolder(folder string) {
	idx := selectedIndices()
	if len(idx) == 0 {
		messageBox(appTitle, "Select at least one challenge first.", MB_OK|MB_ICONWARNING)
		return
	}
	if isaacDir == "" {
		messageBox(appTitle, "Could not find The Binding of Isaac Rebirth installation.\n\nMove this exporter into the game's main folder and run it again, or make sure Steam is installed normally.", MB_OK|MB_ICONERROR)
		return
	}

	selected := make([]Challenge, 0, len(idx))
	for _, i := range idx {
		selected = append(selected, challenges[i])
	}

	modsDir := filepath.Join(isaacDir, "mods")
	namedDir := filepath.Join(modsDir, folder)
	files, total, err := prepareFolderExport(modsDir, folder, selected, challenges)
	if err != nil {
		messageBox(appTitle, "Could not prepare export:\n"+err.Error(), MB_OK|MB_ICONERROR)
		return
	}

	for path, contents := range files {
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			messageBox(appTitle, "Could not create export folder:\n"+err.Error(), MB_OK|MB_ICONERROR)
			return
		}
		if err := os.WriteFile(path, []byte(contents), 0644); err != nil {
			messageBox(appTitle, "Could not write:\n"+path+"\n\n"+err.Error(), MB_OK|MB_ICONERROR)
			return
		}
	}

	messageBox(appTitle, fmt.Sprintf("Exported %d challenge(s) to:\n%s\n\n%d challenges in this independent pack. Enable the pack in Mods and restart Isaac.", len(selected), namedDir, total), MB_OK|MB_ICONINFO)
}

func xmlEscape(s string) string {
	replacer := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;", "'", "&apos;")
	return replacer.Replace(s)
}

func buildChallengesXML(cs []Challenge) string {
	var b strings.Builder
	b.WriteString("<challenges version=\"1\">\r\n")
	for _, c := range cs {
		title := strings.TrimSpace(c.Title)
		if title == "" {
			title = "Generated Challenge"
		}
		playerType := c.PlayerType
		if c.PlayerIsModded {
			playerType = 0
		}
		endStage := c.EndStage
		if endStage <= 0 {
			endStage = 8
		}

		attrs := []string{
			`name="` + xmlEscape(title) + `"`,
			`playertype="` + strconv.Itoa(playerType) + `"`,
			`endstage="` + strconv.Itoa(endStage) + `"`,
		}
		if c.AltPath != nil {
			attrs = append(attrs, `altpath="`+strconv.FormatBool(*c.AltPath)+`"`)
		}
		if c.MegaSatan {
			attrs = append(attrs, `megasatan="true"`)
		}
		if c.SecretPath {
			attrs = append(attrs, `secretpath="true"`)
		}
		if c.Difficulty > 0 {
			attrs = append(attrs, `difficulty="`+strconv.Itoa(c.Difficulty)+`"`)
		}
		// REPENTOGON challenges.xml accepts modded starting collectibles by XML name.
		// Challenge Maker stores those names as StartingItemTokens while vanilla
		// collectibles remain numeric ids. Old saves without tokens still work.
		items := make([]string, 0, len(c.StartingItemTokens)+2)
		if len(c.StartingItemTokens) > 0 {
			for _, token := range c.StartingItemTokens {
				token = strings.TrimSpace(token)
				if token != "" {
					items = append(items, xmlEscape(token))
				}
			}
		} else {
			for _, id := range c.StartingItems {
				items = append(items, strconv.Itoa(id))
			}
		}
		// Route items are part of the challenge definition, not user parameters.
		if c.FinalBossKey == "blue_baby" {
			items = append(items, "327") // The Polaroid
		} else if c.FinalBossKey == "lamb" {
			items = append(items, "328") // The Negative
		}
		if len(items) > 0 {
			attrs = append(attrs, `startingitems="`+strings.Join(items, ",")+`"`)
		}
		if len(c.BannedRooms) > 0 {
			rooms := make([]string, 0, len(c.BannedRooms))
			for _, id := range filteredBannedRooms(c.BannedRooms) {
				// Devil/Angel use Lua policy so one banned side forces the other
				// rather than simply deleting the entire pact system.
				if id != 14 && id != 15 {
					rooms = append(rooms, strconv.Itoa(id))
				}
			}
			if len(rooms) > 0 {
				attrs = append(attrs, `roomfilter="`+strings.Join(rooms, ",")+`"`)
			}
		}
		if c.Blindfold {
			attrs = append(attrs, `canshoot="false"`)
		}
		b.WriteString("    <challenge " + strings.Join(attrs, " ") + " />\r\n")
	}
	b.WriteString("</challenges>\r\n")
	return b.String()
}

func luaQuote(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	s = strings.ReplaceAll(s, "\r", `\r`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	return `"` + s + `"`
}

const noSoulLua = `local function applyNoSoul(config, player)
    if not config or config.noSoul ~= true
        or tonumber(config.playerType) ~= PlayerType.PLAYER_THEFORGOTTEN
        or not player or player:IsDead() then return end
    local pt = player:GetPlayerType()
    if pt == PlayerType.PLAYER_THESOUL then
        -- Restore the bone form using the native swap, preserving both bodies.
        -- Only call this for active players, never the dormant subplayer.
        player:SetForgottenSwapFormCooldown(0)
        player:SwapForgottenForm(true, true)
    elseif pt ~= PlayerType.PLAYER_THEFORGOTTEN then
        return
    end
    -- Keep the native swap cooldown nonzero. Drop/trinket controls still work.
    player:SetForgottenSwapFormCooldown(2)
end

`

func buildGeneratedLua(cs []Challenge) string {
	var b strings.Builder
	b.WriteString("local mod = RegisterMod(\"Challenge Maker Exported\", 1)\n")
	b.WriteString("local game = Game()\n\n")
	b.WriteString("local general = include(\"cm_general\")\n")
	b.WriteString(noSoulLua)
	b.WriteString("local configsByName = {\n")
	for _, c := range cs {
		banned := make([]string, 0)
		if len(c.BannedItemTokens) > 0 {
			for _, token := range c.BannedItemTokens {
				token = strings.TrimSpace(token)
				if token != "" {
					banned = append(banned, token)
				}
			}
		} else {
			for _, id := range c.BannedItems {
				banned = append(banned, strconv.Itoa(id))
			}
		}
		b.WriteString("    [" + luaQuote(c.Title) + "] = {\n")
		b.WriteString("        playerType = " + strconv.Itoa(c.PlayerType) + ",\n")
		b.WriteString("        playerIsModded = " + strconv.FormatBool(c.PlayerIsModded) + ",\n")
		b.WriteString("        playerToken = " + luaQuote(c.PlayerToken) + ",\n")
		b.WriteString("        blindfold = " + strconv.FormatBool(c.Blindfold) + ",\n")
		b.WriteString("        startStats = {")
		for _, key := range []string{"speed", "tears", "damage", "range", "shot_speed", "luck"} {
			if value, ok := c.StartStats[key]; ok && value >= -100 && value <= 100 {
				b.WriteString("[" + luaQuote(key) + "]=" + strconv.FormatFloat(value, 'f', -1, 64) + ",")
			}
		}
		b.WriteString("},\n")
		b.WriteString("        startHealth = {")
		for _, key := range []string{"containers", "red", "soul", "black", "bone", "rotten"} {
			if v, ok := c.StartHealth[key]; ok && v >= 0 && v <= 48 {
				b.WriteString("[" + luaQuote(key) + "]=" + strconv.Itoa(v) + ",")
			}
		}
		b.WriteString("}, startCharges = {")
		for _, key := range []string{"activeCharge", "pocketCharge"} {
			if v, ok := c.StartCharges[key]; ok && v >= 0 && v <= 99 {
				b.WriteString("[" + luaQuote(key) + "]=" + strconv.Itoa(v) + ",")
			}
		}
		b.WriteString("}, curseModes = {")
		for _, key := range []string{"darkness", "lost", "unknown", "blind", "maze"} {
			if mode := c.CurseModes[key]; mode == "required" || mode == "forbidden" {
				b.WriteString("[" + luaQuote(key) + "]=" + luaQuote(mode) + ",")
			}
		}
		b.WriteString("},\n")
		for _, entry := range []struct {
			name  string
			value *int
		}{{"startCoins", c.StartCoins}, {"startBombs", c.StartBombs}, {"startKeys", c.StartKeys}} {
			if entry.value != nil && *entry.value >= 0 && *entry.value <= 99 {
				b.WriteString("        " + entry.name + " = " + strconv.Itoa(*entry.value) + ",\n")
			}
		}
		b.WriteString("        startingPickups = {\n")
		for _, pickup := range c.StartingPickups {
			b.WriteString("            {kind=" + luaQuote(pickup.Kind) + ", id=" + strconv.Itoa(pickup.ID) + ", token=" + luaQuote(pickup.Token) + ", delivery=" + luaQuote(pickup.Delivery) + "},\n")
		}
		b.WriteString("        },\n")
		b.WriteString("        bannedPickups = {\n")
		for _, pickup := range c.BannedPickups {
			b.WriteString("            {kind=" + luaQuote(pickup.Kind) + ", id=" + strconv.Itoa(pickup.ID) + ", token=" + luaQuote(pickup.Token) + ", delivery=" + luaQuote(pickup.Delivery) + "},\n")
		}
		b.WriteString("        },\n")
		b.WriteString("        bannedPools = {\n")
		for _, pool := range c.BannedPools {
			b.WriteString("            {id=" + strconv.Itoa(pool.ID) + ", name=" + luaQuote(pool.Name) + "},\n")
		}
		b.WriteString("        },\n")
		b.WriteString("        noSoul = " + strconv.FormatBool(c.NoSoul && c.PlayerType == 16) + ",\n")
		b.WriteString("        transformations = {\n")
		for _, tr := range c.Transformations {
			b.WriteString("            {id=" + strconv.Itoa(tr.ID) + ", key=" + luaQuote(tr.Key) + ", special=" + luaQuote(tr.Special) + "},\n")
		}
		b.WriteString("        },\n")
		b.WriteString("        megaSatan = " + strconv.FormatBool(c.MegaSatan || c.FinalBossKey == "mega_satan") + ",\n")
		b.WriteString("        mother = " + strconv.FormatBool(c.FinalBossKey == "mother") + ",\n")
		b.WriteString("        bannedRooms = {")
		for i, roomType := range filteredBannedRooms(c.BannedRooms) {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(strconv.Itoa(roomType))
		}
		b.WriteString("},\n")
		b.WriteString("        banned = {")
		for i, token := range banned {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(luaQuote(token))
		}
		b.WriteString("},\n")
		b.WriteString("        description = " + luaQuote(c.Description) + ",\n")
		b.WriteString("    },\n")
	}
	b.WriteString("}\n\n")
	b.WriteString("local configsById = {}\n")
	b.WriteString("local activeConfig = nil\n")
	b.WriteString("local banGuard = include(\"cm_bans\").Attach(mod, game, function() if activeConfig == configsById[Isaac.GetChallenge()] then return activeConfig end end)\n")
	b.WriteString("local bannedSet = {}\n")
	b.WriteString("local bannedRoomSet = {}\n")
	b.WriteString("local bannedCards, bannedPills, bannedPillColors, bannedTrinkets = {}, {}, {}, {}\n")
	b.WriteString("local allowedPills = nil\n")
	b.WriteString("local startingPickupsApplied = false\n")
	b.WriteString("local START_STAT_FLAGS = CacheFlag.CACHE_SPEED | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_RANGE | CacheFlag.CACHE_SHOTSPEED | CacheFlag.CACHE_LUCK\n")
	b.WriteString("function mod:OnStartingStatCache(player,flag)\n")
	b.WriteString("    if not activeConfig or not player or game:GetNumPlayers()<1 or GetPtrHash(player)~=GetPtrHash(Isaac.GetPlayer(0)) then return end\n")
	b.WriteString("    local s=activeConfig.startStats or {}\n")
	b.WriteString("    if flag==CacheFlag.CACHE_SPEED then player.MoveSpeed=math.max(0.1,player.MoveSpeed+(tonumber(s.speed) or 0))\n")
	b.WriteString("    elseif flag==CacheFlag.CACHE_RANGE then player.TearRange=math.max(40,player.TearRange+40*(tonumber(s.range) or 0))\n")
	b.WriteString("    elseif flag==CacheFlag.CACHE_SHOTSPEED then player.ShotSpeed=math.max(0.1,player.ShotSpeed+(tonumber(s.shot_speed) or 0))\n")
	b.WriteString("    elseif flag==CacheFlag.CACHE_LUCK then player.Luck=player.Luck+(tonumber(s.luck) or 0)\n")
	b.WriteString("    elseif flag==CacheFlag.CACHE_FIREDELAY then local old=math.max(0.1,30/(math.max(-0.99,player.MaxFireDelay)+1));player.MaxFireDelay=30/math.max(0.1,old+(tonumber(s.tears) or 0))-1 end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnStartingDamageStat(player,stage,value)\n")
	b.WriteString("    if stage~=EvaluateStatStage.FLAT_DAMAGE or not activeConfig or not player or game:GetNumPlayers()<1 or GetPtrHash(player)~=GetPtrHash(Isaac.GetPlayer(0)) then return end\n")
	b.WriteString("    local s=activeConfig.startStats or {}\n")
	b.WriteString("    local bonus=tonumber(s.damage) or 0\n")
	b.WriteString("    if bonus~=0 then return math.max(0.1,value+bonus) end\n")
	b.WriteString("end\n\n")
	b.WriteString("local pickupCatalog = nil\n")
	b.WriteString("local spindownFixFrames = 0\n")
	b.WriteString("local BANNABLE_ROOM_TYPES = {[2]=true,[4]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true,[18]=true,[19]=true,[20]=true,[21]=true,[22]=true,[24]=true,[29]=true}\n\n")
	b.WriteString("local function resolvePlayerType(cfg)\n")
	b.WriteString("    if not cfg then return 0 end\n")
	b.WriteString("    if cfg.playerIsModded and type(cfg.playerToken) == 'string' and cfg.playerToken ~= '' then\n")
	b.WriteString("        local ok,id=pcall(function() return Isaac.GetPlayerTypeByName(cfg.playerToken,false) end)\n")
	b.WriteString("        if ok and type(id)=='number' and id>=0 then return id end\n")
	b.WriteString("        local okT,idT=pcall(function() return Isaac.GetPlayerTypeByName(cfg.playerToken,true) end)\n")
	b.WriteString("        if okT and type(idT)=='number' and idT>=0 then return idT end\n")
	b.WriteString("    end\n")
	b.WriteString("    return tonumber(cfg.playerType or 0) or 0\n")
	b.WriteString("end\n\n")
	b.WriteString("local function enforceCharacter(cfg)\n")
	b.WriteString("    if not cfg or not cfg.playerIsModded or game:GetNumPlayers() < 1 then return end\n")
	b.WriteString("    local p=Isaac.GetPlayer(0); local wanted=resolvePlayerType(cfg)\n")
	b.WriteString("    if p and p:GetPlayerType() ~= wanted then\n")
	b.WriteString("        local changed = pcall(function() p:ChangePlayerType(wanted) end)\n")
	b.WriteString("        if changed then\n")
	b.WriteString("            pcall(function() p:InitPostLevelInitStats() end)\n")
	b.WriteString("            pcall(function() p:AddCacheFlags(CacheFlag.CACHE_ALL); p:EvaluateItems() end)\n")
	b.WriteString("        end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")

	b.WriteString("local function refreshChallengeIds()\n")
	b.WriteString("    configsById = {}\n")
	b.WriteString("    for name, cfg in pairs(configsByName) do\n")
	b.WriteString("        local id = Isaac.GetChallengeIdByName(name)\n")
	b.WriteString("        if id and id > 0 then configsById[id] = cfg end\n")
	b.WriteString("    end\n")
	b.WriteString("    activeConfig = configsById[Isaac.GetChallenge()]\n")
	b.WriteString("end\n\n")
	b.WriteString("local function resolveItem(token)\n")
	b.WriteString("    local numeric = tonumber(token)\n")
	b.WriteString("    if numeric and numeric > 0 then return numeric end\n")
	b.WriteString("    if type(token) == \"string\" and token ~= \"\" then\n")
	b.WriteString("        local ok, id = pcall(function() return Isaac.GetItemIdByName(token) end)\n")
	b.WriteString("        if ok and type(id) == \"number\" and id > 0 then return id end\n")
	b.WriteString("    end\n")
	b.WriteString("    return nil\n")
	b.WriteString("end\n\n")
	b.WriteString("local function resolvePickup(kind, token, fallback)\n")
	b.WriteString("    local numeric = tonumber(token) or tonumber(fallback)\n")
	b.WriteString("    if numeric and numeric > 0 then return numeric end\n")
	b.WriteString("    if type(token) ~= 'string' or token == '' then return nil end\n")
	b.WriteString("    local ok, id = pcall(function()\n")
	b.WriteString("        if kind == 'card' then return Isaac.GetCardIdByName(token) end\n")
	b.WriteString("        if kind == 'pill' then return Isaac.GetPillEffectByName(token) end\n")
	b.WriteString("        if kind == 'trinket' then return Isaac.GetTrinketIdByName(token) end\n")
	b.WriteString("    end)\n")
	b.WriteString("    if ok and type(id) == 'number' and id > 0 then return id end\n")
	b.WriteString("    return tonumber(fallback)\n")
	b.WriteString("end\n\n")
	b.WriteString("local function rebuildBannedPickupSets()\n")
	b.WriteString("    bannedCards, bannedPills, bannedPillColors, bannedTrinkets = {}, {}, {}, {}; allowedPills = nil\n")
	b.WriteString("    if not activeConfig then return end\n")
	b.WriteString("    enforceCharacter(activeConfig)\n")
	b.WriteString("    local banModPickups, banModTrinkets = false, false\n")
	b.WriteString("    for _, p in ipairs(activeConfig.bannedPickups or {}) do\n")
	b.WriteString("        if p.kind == 'mod_pickups' then banModPickups=true elseif p.kind == 'mod_trinkets' then banModTrinkets=true else\n")
	b.WriteString("            local id = resolvePickup(p.kind, p.token, p.id)\n")
	b.WriteString("            if id then if p.kind == 'card' then bannedCards[id]=true elseif p.kind == 'pill' then bannedPills[id]=true elseif p.kind == 'pill_color' then bannedPillColors[id]=true elseif p.kind == 'trinket' then bannedTrinkets[id]=true end end\n")
	b.WriteString("        end\n")
	b.WriteString("    end\n")
	b.WriteString("    if banModPickups or banModTrinkets then\n")
	b.WriteString("        local nodes={{XMLNode.CARD,'card'},{XMLNode.PILL,'pill'},{XMLNode.TRINKET,'trinket'}}\n")
	b.WriteString("        local function realModSource(src) if src==nil then return false end; local sid=tostring(src); if sid=='' or sid=='0' or sid=='nil' then return false end; local ok,info=pcall(function() return XMLData.GetModById(sid) end); return ok and type(info)=='table' and next(info)~=nil end\n")
	b.WriteString("        for _,pair in ipairs(nodes) do local ok,count=pcall(function() return XMLData.GetNumEntries(pair[1]) end); if ok then for i=1,count do local e=XMLData.GetEntryByOrder(pair[1],i); local id=e and tonumber(e.id); if id and id>0 and realModSource(e.sourceid) then if banModTrinkets and pair[2]=='trinket' then bannedTrinkets[id]=true elseif banModPickups and pair[2]=='card' then bannedCards[id]=true elseif banModPickups and pair[2]=='pill' then bannedPills[id]=true end end end end end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function ensurePickupCatalog()\n")
	b.WriteString("    if pickupCatalog then return end\n")
	b.WriteString("    pickupCatalog = {card={}, pill={}, trinket={}}\n")
	b.WriteString("    local nodes = {{XMLNode.CARD,'card'},{XMLNode.PILL,'pill'},{XMLNode.TRINKET,'trinket'}}\n")
	b.WriteString("    for _, pair in ipairs(nodes) do\n")
	b.WriteString("        local ok, count = pcall(function() return XMLData.GetNumEntries(pair[1]) end)\n")
	b.WriteString("        if ok then for i=1,count do local e=XMLData.GetEntryByOrder(pair[1],i); local id=e and tonumber(e.id); if id and id>0 then table.insert(pickupCatalog[pair[2]],id) end end end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function randomAllowedCard(rng, includePlayingCards, includeRunes, onlyRunes)\n")
	b.WriteString("    ensurePickupCatalog(); local out={}; local root=Isaac.GetItemConfig()\n")
	b.WriteString("    for _,id in ipairs(pickupCatalog.card) do if not bannedCards[id] then local c=root:GetCard(id); if c then local avail=true; pcall(function() avail=c:IsAvailable() end); local rune=false; pcall(function() rune=c:IsRune() end); local suit=tonumber(c.CardType)==tonumber(ItemConfig.CARDTYPE_SUIT); if avail and (not onlyRunes or rune) and (includeRunes or not rune) and (includePlayingCards or not suit) then table.insert(out,id) end end end end\n")
	b.WriteString("    if #out==0 then return nil end; return out[rng:RandomInt(#out)+1]\n")
	b.WriteString("end\n\n")
	b.WriteString("local function randomAllowedTrinket(rng, golden)\n")
	b.WriteString("    ensurePickupCatalog(); local out={}; local pool=game:GetItemPool()\n")
	b.WriteString("    for _,id in ipairs(pickupCatalog.trinket) do if not bannedTrinkets[id] then local avail=true; if pool.HasTrinket then pcall(function() avail=pool:HasTrinket(id) end) end; if avail then table.insert(out,id) end end end\n")
	b.WriteString("    if #out==0 then return nil end; local id=out[rng:RandomInt(#out)+1]; if golden then id=id+(TrinketType.TRINKET_GOLDEN_FLAG or 32768) end; return id\n")
	b.WriteString("end\n\n")
	b.WriteString("local function replacementPill(color)\n")
	b.WriteString("    ensurePickupCatalog(); if not allowedPills then allowedPills={}; local root=Isaac.GetItemConfig(); for _,id in ipairs(pickupCatalog.pill) do if not bannedPills[id] then local c=root:GetPillEffect(id); if c then local avail=true; if c.IsAvailable then pcall(function() avail=c:IsAvailable() end) end; if avail then table.insert(allowedPills,id) end end end end end\n")
	b.WriteString("    if #allowedPills==0 then return nil end; local seed=(tonumber(color) or 0)+game:GetSeeds():GetStartSeed(); return allowedPills[(math.abs(seed)%#allowedPills)+1]\n")
	b.WriteString("end\n\n")
	b.WriteString("local function clearHeldTrinkets(player)\n")
	b.WriteString("    for _=1,4 do local id=player:GetTrinket(0); if not id or id<=0 then break end; if not player:TryRemoveTrinket(id) then break end end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function applyStartingPickups()\n")
	b.WriteString("    if startingPickupsApplied or not activeConfig or game:GetNumPlayers()<=0 then return end\n")
	b.WriteString("    local player=Isaac.GetPlayer(0); local pockets={}; local trinkets={}; local smeltedTrinkets={}\n")
	b.WriteString("    for _,p in ipairs(activeConfig.startingPickups or {}) do local id=resolvePickup(p.kind,p.token,p.id); if id then if p.kind=='card' or p.kind=='pill' or p.kind=='pill_color' then table.insert(pockets,{kind=p.kind,id=id}) elseif p.kind=='trinket' then if (p.delivery or 'normal')=='smelted' then table.insert(smeltedTrinkets,id) else table.insert(trinkets,id) end end end end\n")
	b.WriteString("    if #pockets>0 then pcall(function() player:SetCard(PillCardSlot.PRIMARY,0); player:SetPill(PillCardSlot.PRIMARY,0); player:SetCard(PillCardSlot.SECONDARY,0); player:SetPill(PillCardSlot.SECONDARY,0) end); local pool=game:GetItemPool(); for i,p in ipairs(pockets) do if i>2 then break end; local slot=i==1 and PillCardSlot.PRIMARY or PillCardSlot.SECONDARY; if p.kind=='card' then player:SetCard(slot,p.id) elseif p.kind=='pill_color' then player:SetPill(slot,p.id) else local color=pool:ForceAddPillEffect(p.id); if color and color>0 then player:SetPill(slot,color) end end end end\n")
	b.WriteString("    if #trinkets>0 then clearHeldTrinkets(player); for i,id in ipairs(trinkets) do if i>2 then break end; player:AddTrinket(id,true) end end\n")
	b.WriteString("    for _,id in ipairs(smeltedTrinkets) do if player.AddSmeltedTrinket then player:AddSmeltedTrinket(id,true) end end\n")
	b.WriteString("    startingPickupsApplied=true\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnGetCard(rng, selectedCard, includePlayingCards, includeRunes, onlyRunes) if not activeConfig or not bannedCards[tonumber(selectedCard)] then return nil end; return randomAllowedCard(rng, includePlayingCards==true, includeRunes==true, onlyRunes==true) end\n")
	b.WriteString("function mod:OnGetTrinket(selectedTrinket, rng) if not activeConfig then return nil end; local raw=tonumber(selectedTrinket) or 0; local flag=TrinketType.TRINKET_GOLDEN_FLAG or 32768; local base=raw%flag; if base<=0 or not bannedTrinkets[base] then return nil end; return randomAllowedTrinket(rng,raw>=flag) end\n")
	b.WriteString("function mod:OnGetPillEffect(selectedEffect, pillColor, player) if not activeConfig or not bannedPills[tonumber(selectedEffect)] then return nil end; return replacementPill(pillColor) end\n\n")
	b.WriteString("local function pillColorParts(color) local raw=tonumber(color) or 0; local giant=PillColor.PILL_GIANT_FLAG or 2048; return raw,raw%giant,raw>=giant end\n")
	b.WriteString("local function replacementPillColor(color) local raw,base,horse=pillColorParts(color); local out={}; for c=1,14 do if not bannedPillColors[c] then table.insert(out,c) end end; if #out==0 then return raw end; local seed=raw+game:GetSeeds():GetStartSeed(); local c=out[(math.abs(seed)%#out)+1]; if horse then c=c+(PillColor.PILL_GIANT_FLAG or 2048) end; return c end\n")
	b.WriteString("function mod:OnPrePlayerAddPill(player,color,slot) if not activeConfig then return nil end; local raw,base=pillColorParts(color); if bannedPillColors[base] then return replacementPillColor(raw) end end\n")
	b.WriteString("function mod:OnPillPickupInit(pickup) if not activeConfig or not pickup then return end; local raw,base=pillColorParts(pickup.SubType); if bannedPillColors[base] then local r=replacementPillColor(raw); if r~=raw then pickup:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_PILL,r,true,true,true) end end end\n\n")
	b.WriteString("local function rebuildBannedSet()\n")
	b.WriteString("    bannedSet = banGuard:Build(activeConfig)\n")
	b.WriteString("end\n\n")
	b.WriteString("local function rebuildBannedRoomSet()\n")
	b.WriteString("    bannedRoomSet = {}\n")
	b.WriteString("    if not activeConfig then return end\n")
	b.WriteString("    for _, roomType in ipairs(activeConfig.bannedRooms or {}) do\n")
	b.WriteString("        local id = tonumber(roomType)\n")
	b.WriteString("        if id and BANNABLE_ROOM_TYPES[id] then bannedRoomSet[id] = true end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function dealBanState(config)\n")
	b.WriteString("    if not config then return false, false end\n")
	b.WriteString("    local devil, angel = false, false\n")
	b.WriteString("    for _, roomType in ipairs(config.bannedRooms or {}) do\n")
	b.WriteString("        local id = tonumber(roomType)\n")
	b.WriteString("        if id == RoomType.ROOM_DEVIL then devil = true elseif id == RoomType.ROOM_ANGEL then angel = true end\n")
	b.WriteString("    end\n")
	b.WriteString("    return devil, angel\n")
	b.WriteString("end\n\n")
	b.WriteString("local function syncDealChanceHUD(config)\n")
	b.WriteString("    if not config then return end\n")
	b.WriteString("    local devilBanned, angelBanned = dealBanState(config)\n")
	b.WriteString("    if devilBanned == angelBanned then return end\n")
	b.WriteString("    local target = devilBanned and 0.5 or -0.5\n")
	b.WriteString("    local level = game:GetLevel()\n")
	b.WriteString("    pcall(function()\n")
	b.WriteString("        local current = tonumber(level:GetAngelRoomChance()) or 0\n")
	b.WriteString("        local delta = target - current\n")
	b.WriteString("        if math.abs(delta) > 0.0001 then level:AddAngelRoomChance(delta) end\n")
	b.WriteString("    end)\n")
	b.WriteString("end\n\n")
	b.WriteString("local function enforceDealPolicy(config)\n")
	b.WriteString("    if not config then return end\n")
	b.WriteString("    local devilBanned, angelBanned = dealBanState(config)\n")
	b.WriteString("    if not devilBanned and not angelBanned then return end\n")
	b.WriteString("    local level = game:GetLevel()\n")
	b.WriteString("    if devilBanned and angelBanned then return end\n")
	b.WriteString("    pcall(function() level:InitializeDevilAngelRoom(devilBanned and not angelBanned, angelBanned and not devilBanned) end)\n")
	b.WriteString("    syncDealChanceHUD(config)\n")
	b.WriteString("end\n\n")
	b.WriteString("local function removeBannedFromPools()\n")
	b.WriteString("    rebuildBannedSet()\n")
	b.WriteString("    local pool = game:GetItemPool()\n")
	b.WriteString("    for id, _ in pairs(bannedSet) do pcall(function() pool:RemoveCollectible(id) end) end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function hasTransformation(key)\n")
	b.WriteString("    if not activeConfig then return false end\n")
	b.WriteString("    for _,tr in ipairs(activeConfig.transformations or {}) do if tostring(tr.key or '')==key then return true end end\n")
	b.WriteString("    return false\n")
	b.WriteString("end\n\n")
	b.WriteString("local function resolveFormId(key,fallback)\n")
	b.WriteString("    if key=='necromancer' then\n")
	b.WriteString("        local enumId=nil; pcall(function() if PlayerForm then enumId=tonumber(PlayerForm.PLAYERFORM_NECROMANCER or PlayerForm.NECROMANCER) end end); if enumId then return enumId end\n")
	b.WriteString("        local resolved=nil; pcall(function() local e=XMLData.GetEntryByName(XMLNode.PLAYERFORM,'Necromancer'); if type(e)=='table' then resolved=tonumber(e.id) end end); if resolved then return resolved end\n")
	b.WriteString("        pcall(function() local n=tonumber(XMLData.GetNumEntries(XMLNode.PLAYERFORM)) or 0; for i=1,n do local e=XMLData.GetEntryByOrder(XMLNode.PLAYERFORM,i); if type(e)=='table' and string.lower(tostring(e.name or ''))=='necromancer' then resolved=tonumber(e.id); break end end end); if resolved then return resolved end\n")
	b.WriteString("    end\n")
	b.WriteString("    return tonumber(fallback)\n")
	b.WriteString("end\n\n")
	b.WriteString("local function ensureSuperBum(player)\n")
	b.WriteString("    if not player then return end; local variant=(FamiliarVariant and FamiliarVariant.SUPER_BUM) or 102\n")
	b.WriteString("    for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,variant,-1,false,false)) do local f=e:ToFamiliar(); if f and f.Player and GetPtrHash(f.Player)==GetPtrHash(player) then return end end\n")
	b.WriteString("    local checked=false; pcall(function() local rng=RNG(); rng:SetSeed(game:GetSeeds():GetStartSeed(),35); player:CheckFamiliar(variant,1,rng,nil,-1); checked=true end)\n")
	b.WriteString("    if not checked then pcall(function() local e=Isaac.Spawn(EntityType.ENTITY_FAMILIAR,variant,0,player.Position,Vector.Zero,player); local f=e and e:ToFamiliar() or nil; if f then f.Player=player end end) end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function applyTransformations(player)\n")
	b.WriteString("    if not activeConfig or not player then return end\n")
	b.WriteString("    local changed=false; local fam=false\n")
	b.WriteString("    for _,tr in ipairs(activeConfig.transformations or {}) do\n")
	b.WriteString("        local stored=tonumber(tr.id); local key=tostring(tr.key or ''); local id=resolveFormId(key,stored)\n")
	b.WriteString("        if key=='super_bum' or stored==-1 then fam=true; ensureSuperBum(player)\n")
	b.WriteString("        elseif id and id>=0 then\n")
	b.WriteString("            if key=='necromancer' then local nec=(CollectibleType and CollectibleType.COLLECTIBLE_NECRONOMICON) or 35; pcall(function() while player:HasCollectible(nec) do player:RemoveCollectible(nec) end; for pickup=1,3 do player:AddCollectible(nec,0,true); if pickup<3 then player:RemoveCollectible(nec) end end end) end\n")
	b.WriteString("            local current=0; local ok,v=pcall(function() return player:GetPlayerFormCounter(id) end); if ok and type(v)=='number' then current=v end\n")
	b.WriteString("            local target=3; if current<target then local ok2=pcall(function() player:IncrementPlayerFormCounter(id,target-current) end); if ok2 then changed=true end end\n")
	b.WriteString("        end\n")
	b.WriteString("    end\n")
	b.WriteString("    if changed or fam then pcall(function() if fam then player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS) end; if changed then player:AddCacheFlags(CacheFlag.CACHE_ALL) end; player:EvaluateItems() end) end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnTransformationCache(player,flag) if flag==CacheFlag.CACHE_FAMILIARS and activeConfig and hasTransformation('super_bum') then ensureSuperBum(player) end end\n\n")
	b.WriteString("local function applyPlayerRules(player)\n")
	b.WriteString("    if not activeConfig or not player or not player:Exists() then return end\n")
	b.WriteString("    if activeConfig.blindfold then\n")
	b.WriteString("        pcall(function() player:AddNullCostume(NullItemID.ID_BLINDFOLD) end)\n")
	b.WriteString("        pcall(function() player:SetCanShoot(false) end)\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function giveRouteItems(player)\n")
	b.WriteString("    if not activeConfig or not player then return end\n")
	b.WriteString("    if activeConfig.megaSatan then\n")
	b.WriteString("        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1) then player:AddCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, 0, true) end\n")
	b.WriteString("        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2) then player:AddCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2, 0, true) end\n")
	b.WriteString("    end\n")
	b.WriteString("    if activeConfig.mother then\n")
	b.WriteString("        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_1) then player:AddCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_1, 0, true) end\n")
	b.WriteString("        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_2) then player:AddCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_2, 0, true) end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function nextAllowedSpindownId(startId)\n")
	b.WriteString("    local cfg = Isaac.GetItemConfig()\n")
	b.WriteString("    local id = tonumber(startId or 0) or 0\n")
	b.WriteString("    while id > 0 do\n")
	b.WriteString("        if not bannedSet[id] then\n")
	b.WriteString("            local ok, item = pcall(function() return cfg:GetCollectible(id) end)\n")
	b.WriteString("            if ok and item and not item.Hidden then return id end\n")
	b.WriteString("        end\n")
	b.WriteString("        id = id - 1\n")
	b.WriteString("    end\n")
	b.WriteString("    return 0\n")
	b.WriteString("end\n\n")
	b.WriteString("local function fixSpindownPedestals()\n")
	b.WriteString("    if not activeConfig or not next(bannedSet) then return end\n")
	b.WriteString("    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)) do\n")
	b.WriteString("        local pickup = entity:ToPickup()\n")
	b.WriteString("        if pickup and bannedSet[pickup.SubType] then\n")
	b.WriteString("            local replacement = nextAllowedSpindownId(pickup.SubType - 1)\n")
	b.WriteString("            if replacement > 0 then\n")
	b.WriteString("                pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, replacement, true, true, true)\n")
	b.WriteString("            else pickup:Remove() end\n")
	b.WriteString("        end\n")
	b.WriteString("    end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnPlayerInit(player)\n")
	b.WriteString("    refreshChallengeIds()\n")
	b.WriteString("    applyPlayerRules(player)\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnGameStart(isContinued)\n")
	b.WriteString("    refreshChallengeIds()\n")
	b.WriteString("    spindownFixFrames = 0\n")
	b.WriteString("    startingPickupsApplied = isContinued == true\n")
	b.WriteString("    if not activeConfig then bannedSet = {}; bannedCards={}; bannedPills={}; bannedPillColors={}; bannedTrinkets={}; allowedPills=nil; return end\n")
	b.WriteString("    enforceCharacter(activeConfig)\n")
	b.WriteString("    removeBannedFromPools()\n")
	b.WriteString("    rebuildBannedPickupSets()\n")
	b.WriteString("    rebuildBannedRoomSet()\n")
	b.WriteString("    enforceDealPolicy(activeConfig)\n")
	b.WriteString("    for i = 0, game:GetNumPlayers() - 1 do applyPlayerRules(Isaac.GetPlayer(i)) end\n")
	b.WriteString("    for i = 0, game:GetNumPlayers() - 1 do applyNoSoul(activeConfig, Isaac.GetPlayer(i)) end\n")
	b.WriteString("    if not startingPickupsApplied then applyStartingPickups() end\n")
	b.WriteString("    if not isContinued and game:GetNumPlayers() > 0 then giveRouteItems(Isaac.GetPlayer(0)); applyStartingPickups() end\n")
	b.WriteString("    if not isContinued and game:GetNumPlayers() > 0 then general.ApplyStart(activeConfig,Isaac.GetPlayer(0)) end\n")
	b.WriteString("    general.ApplyCurses(activeConfig,game:GetLevel())\n")
	b.WriteString("    if game:GetNumPlayers() > 0 then applyTransformations(Isaac.GetPlayer(0)) end\n")
	b.WriteString("    if game:GetNumPlayers() > 0 and activeConfig.startStats and next(activeConfig.startStats) then local player=Isaac.GetPlayer(0);player:AddCacheFlags(START_STAT_FLAGS);player:EvaluateItems() end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnUseSpindown()\n")
	b.WriteString("    if activeConfig and next(bannedSet) then spindownFixFrames = 3 end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnUpdate()\n")
	b.WriteString("    if not activeConfig then return end\n")
	b.WriteString("    for i = 0, game:GetNumPlayers() - 1 do applyNoSoul(activeConfig, Isaac.GetPlayer(i)) end\n")
	b.WriteString("    if game:GetNumPlayers() > 0 then applyTransformations(Isaac.GetPlayer(0)) end\n")
	b.WriteString("    if activeConfig.blindfold then\n")
	b.WriteString("        for i = 0, game:GetNumPlayers() - 1 do pcall(function() Isaac.GetPlayer(i):SetCanShoot(false) end) end\n")
	b.WriteString("    end\n")
	b.WriteString("    if spindownFixFrames > 0 then spindownFixFrames = spindownFixFrames - 1 fixSpindownPedestals() end\n")
	b.WriteString("end\n\n")
	b.WriteString("local function currentConfig()\n")
	b.WriteString("    local cfg = configsById[Isaac.GetChallenge()]\n")
	b.WriteString("    if cfg then activeConfig = cfg end\n")
	b.WriteString("    return cfg\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnPostNewLevel()\n")
	b.WriteString("    local cfg = currentConfig() if not cfg then return end\n")
	b.WriteString("    rebuildBannedRoomSet()\n")
	b.WriteString("    enforceDealPolicy(cfg)\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnPostDevilCalculate(chance)\n")
	b.WriteString("    local cfg = currentConfig() if not cfg then return end\n")
	b.WriteString("    local devilBanned, angelBanned = dealBanState(cfg)\n")
	b.WriteString("    if devilBanned and angelBanned then return 0.0 end\n")
	b.WriteString("end\n\n")
	b.WriteString("function mod:OnDealHudUpdate()\n")
	b.WriteString("    local cfg = currentConfig() if not cfg then return end\n")
	b.WriteString("    syncDealChanceHUD(cfg)\n")
	b.WriteString("end\n\n")
	b.WriteString("refreshChallengeIds()\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, mod.OnPlayerInit)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnTransformationCache, CacheFlag.CACHE_FAMILIARS)\n")
	b.WriteString("for _,flag in ipairs({CacheFlag.CACHE_SPEED,CacheFlag.CACHE_FIREDELAY,CacheFlag.CACHE_RANGE,CacheFlag.CACHE_SHOTSPEED,CacheFlag.CACHE_LUCK}) do mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE,mod.OnStartingStatCache,flag) end\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_EVALUATE_STAT,mod.OnStartingDamageStat,EvaluateStatStage.FLAT_DAMAGE)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_GET_CARD, mod.OnGetCard)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_GET_TRINKET, mod.OnGetTrinket)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_GET_PILL_EFFECT, mod.OnGetPillEffect)\n")
	b.WriteString("if ModCallbacks.MC_PRE_PLAYER_ADD_PILL then mod:AddCallback(ModCallbacks.MC_PRE_PLAYER_ADD_PILL, mod.OnPrePlayerAddPill) end\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, mod.OnPillPickupInit, PickupVariant.PICKUP_PILL)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnPillPickupInit, PickupVariant.PICKUP_PILL)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseSpindown, CollectibleType.COLLECTIBLE_SPINDOWN_DICE)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnDealHudUpdate)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.OnPostNewLevel)\n")
	b.WriteString("mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL,function() if activeConfig then general.ApplyCurses(activeConfig,game:GetLevel()) end end)\n")
	b.WriteString("if ModCallbacks.MC_POST_DEVIL_CALCULATE then mod:AddCallback(ModCallbacks.MC_POST_DEVIL_CALCULATE, mod.OnPostDevilCalculate) end\n")
	rules := make(map[string]json.RawMessage, len(cs))
	for _, c := range cs {
		value := c.Conditions
		if len(value) == 0 || string(value) == "null" {
			value = json.RawMessage("[]")
		}
		rules[c.Title] = value
	}
	encoded, err := json.Marshal(rules)
	if err != nil {
		panic("invalid saved conditions: " + err.Error())
	}
	delimiter := "="
	for strings.Contains(string(encoded), "]"+delimiter+"]") {
		delimiter += "="
	}
	b.WriteString("\nlocal exportedConditionsJSON = [" + delimiter + "[" + string(encoded) + "]" + delimiter + "]\n")
	b.WriteString(conditionsAdapterLua)
	return b.String()
}

func readChallenges(gameDir string) []Challenge {
	readWarnings = nil
	dataDir := filepath.Join(gameDir, "data")
	type fileInfo struct {
		path, slot string
		mod        time.Time
	}
	var files []fileInfo

	exact := filepath.Join(dataDir, "challenge_maker")
	for i := 1; i <= 3; i++ {
		p := filepath.Join(exact, fmt.Sprintf("save%d.dat", i))
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			files = append(files, fileInfo{p, fmt.Sprintf("Save %d", i), st.ModTime()})
		}
	}

	// Fallback: scan one directory deep in case the installed folder name differs.
	if len(files) == 0 {
		entries, _ := os.ReadDir(dataDir)
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			for i := 1; i <= 3; i++ {
				p := filepath.Join(dataDir, entry.Name(), fmt.Sprintf("save%d.dat", i))
				st, err := os.Stat(p)
				if err != nil || st.IsDir() {
					continue
				}
				raw, err := os.ReadFile(p)
				if err != nil || !strings.Contains(string(raw), "challengeMakerVersion") {
					continue
				}
				files = append(files, fileInfo{p, fmt.Sprintf("Save %d", i), st.ModTime()})
			}
		}
	}

	sort.Slice(files, func(i, j int) bool { return files[i].mod.Before(files[j].mod) })
	byChallenge := map[string]challengeWithSource{}
	for _, f := range files {
		raw, err := os.ReadFile(f.path)
		if err != nil {
			readWarnings = append(readWarnings, f.path+": "+err.Error())
			continue
		}
		var store struct {
			Challenges []json.RawMessage `json:"challenges"`
		}
		if err := json.Unmarshal(raw, &store); err != nil {
			readWarnings = append(readWarnings, f.path+": "+err.Error())
			continue
		}
		for index, entry := range store.Challenges {
			var c Challenge
			if err := json.Unmarshal(entry, &c); err != nil {
				readWarnings = append(readWarnings, fmt.Sprintf("%s, challenge %d: %s", f.path, index+1, err))
				continue
			}
			c.Title = strings.TrimSpace(c.Title)
			if c.Title == "" {
				continue
			}
			if c.EndStage <= 0 {
				c.EndStage = 8
			}
			id := strings.TrimSpace(c.ID)
			key := ""
			if id != "" {
				key = "id:" + strings.ToLower(id)
			} else {
				// Legacy saves may not have an id. Keep title fallback only for those.
				key = "title:" + strings.ToLower(c.Title)
			}
			byChallenge[key] = challengeWithSource{Challenge: c, ModTime: f.mod, Slot: f.slot}
		}
	}

	out := make([]Challenge, 0, len(byChallenge))
	for _, item := range byChallenge {
		out = append(out, item.Challenge)
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Title) < strings.ToLower(out[j].Title) })
	return out
}

func candidateSteamRoots() []string {
	var roots []string
	add := func(p string) {
		p = strings.Trim(strings.TrimSpace(p), `"`)
		if p == "" {
			return
		}
		p = filepath.Clean(p)
		for _, e := range roots {
			if strings.EqualFold(e, p) {
				return
			}
		}
		roots = append(roots, p)
	}

	// Steam registry paths through reg.exe; avoids extra dependencies.
	queries := [][]string{
		{"query", `HKCU\Software\Valve\Steam`, "/v", "SteamPath"},
		{"query", `HKLM\SOFTWARE\WOW6432Node\Valve\Steam`, "/v", "InstallPath"},
	}
	for _, args := range queries {
		cmd := exec.Command("reg.exe", args...)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		if out, err := cmd.Output(); err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if strings.Contains(line, "REG_SZ") {
					parts := strings.SplitN(line, "REG_SZ", 2)
					if len(parts) == 2 {
						add(parts[1])
					}
				}
			}
		}
	}

	// Common locations, including D:\Steam (the common custom-library layout).
	for drive := 'C'; drive <= 'Z'; drive++ {
		root := fmt.Sprintf("%c:\\", drive)
		if _, err := os.Stat(root); err != nil {
			continue
		}
		add(filepath.Join(root, "Steam"))
		add(filepath.Join(root, "SteamLibrary"))
		add(filepath.Join(root, "Program Files (x86)", "Steam"))
		add(filepath.Join(root, "Program Files", "Steam"))
	}

	// If the exporter is placed in the Isaac folder, detect that too.
	if exe, err := os.Executable(); err == nil {
		add(filepath.Dir(exe))
	}
	if cwd, err := os.Getwd(); err == nil {
		add(cwd)
	}

	// Parse libraryfolders.vdf from every Steam root we already know.
	pathRe := regexp.MustCompile(`(?i)"path"\s+"([^"]+)"`)
	initial := append([]string(nil), roots...)
	for _, root := range initial {
		vdf := filepath.Join(root, "steamapps", "libraryfolders.vdf")
		raw, err := os.ReadFile(vdf)
		if err != nil {
			continue
		}
		for _, m := range pathRe.FindAllStringSubmatch(string(raw), -1) {
			if len(m) == 2 {
				add(strings.ReplaceAll(m[1], `\\`, `\`))
			}
		}
	}
	return roots
}

func findIsaacDir() string {
	// Direct environment override for unusual setups.
	if env := os.Getenv("ISAAC_GAME_DIR"); env != "" {
		if isIsaacDir(env) {
			return filepath.Clean(env)
		}
	}

	// If the exporter is kept inside mods/challenge_maker/tools, walk upward
	// so it can find the game without relying on Steam registry detection.
	starts := []string{}
	if exe, err := os.Executable(); err == nil {
		starts = append(starts, filepath.Dir(exe))
	}
	if cwd, err := os.Getwd(); err == nil {
		starts = append(starts, cwd)
	}
	for _, start := range starts {
		cur := filepath.Clean(start)
		for i := 0; i < 8; i++ {
			if isIsaacDir(cur) {
				return cur
			}
			parent := filepath.Dir(cur)
			if parent == cur {
				break
			}
			cur = parent
		}
	}

	for _, root := range candidateSteamRoots() {
		candidates := []string{
			root,
			filepath.Join(root, "steamapps", "common", "The Binding of Isaac Rebirth"),
		}
		for _, c := range candidates {
			if isIsaacDir(c) {
				return filepath.Clean(c)
			}
		}
	}
	return ""
}

func isIsaacDir(p string) bool {
	if p == "" {
		return false
	}
	st, err := os.Stat(p)
	if err != nil || !st.IsDir() {
		return false
	}
	if _, err := os.Stat(filepath.Join(p, "mods")); err != nil {
		return false
	}
	if _, err := os.Stat(filepath.Join(p, "data")); err != nil {
		return false
	}
	return true
}

func main() {
	// Win32 windows and their message queue belong to the creating OS thread.
	// Keep creation, callbacks, and GetMessage on that thread for the full UI lifetime.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	isaacDir = findIsaacDir()
	if isaacDir != "" {
		challenges = readChallenges(isaacDir)
	}

	hInst, _, _ := procGetModuleHandleW.Call(0)
	cursor, _, _ := procLoadCursorW.Call(0, IDC_ARROW)
	font, _, _ := procGetStockObject.Call(DEFAULT_GUI_FONT)
	guiFont = font

	className := utf16Ptr("ChallengeMakerExporterWindow")
	wc := WNDCLASSEX{
		CbSize:        uint32(unsafe.Sizeof(WNDCLASSEX{})),
		LpfnWndProc:   syscall.NewCallback(wndProc),
		HInstance:     syscall.Handle(hInst),
		HCursor:       syscall.Handle(cursor),
		HbrBackground: syscall.Handle(COLOR_WINDOW + 1),
		LpszClassName: className,
	}
	if r, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc))); r == 0 {
		return
	}

	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(utf16Ptr(appTitle))),
		WS_OVERLAPPEDWINDOW|WS_VISIBLE,
		uintptr(CW_USEDEFAULT), uintptr(CW_USEDEFAULT), 630, 525,
		0, 0, hInst, 0,
	)
	if hwnd == 0 {
		return
	}
	hMain = syscall.Handle(hwnd)
	procShowWindow.Call(hwnd, SW_SHOWDEFAULT)
	procUpdateWindow.Call(hwnd)

	var msg MSG
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}
}
