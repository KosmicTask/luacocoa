#!/Library/Frameworks/LuaCocoa.framework/Versions/Current/Tools/luacocoa
--[[
Adopted from Matt Gallagher's blog post:
Minimalist Cocoa programming
http://cocoawithlove.com/2010/09/minimalist-cocoa-programming.html?utm_source=feedburner&utm_medium=feed&utm_campaign=Feed%3A+CocoaWithLove+%28Cocoa+with+Love%29
I believe this program requires 10.6+ because of setActivationPolicy.
--]]

LuaCocoa.import("Foundation")
LuaCocoa.import("AppKit")

-- Hmmm...NSApp is a corner-case I need to fix in the Bridge.
-- NSApp is a "constant" (in the loosest sense), 
-- but doesn't get set until after NSApplication is initialized.
-- The current Bridge implementation loads all constants before
-- this happens so NSApp is nil.
-- So make sure to assign NSApp here.
NSApp = NSApplication:sharedApplication()

-- 10.6 API
NSApp:setActivationPolicy_(NSApplicationActivationPolicyRegular)

local menu_bar = NSMenu:alloc():init()
local app_menu_item = NSMenuItem:alloc():init()
menu_bar:addItem_(app_menu_item)
NSApp:setMainMenu_(menu_bar)
local app_menu = NSMenu:alloc():init()
local app_name = NSProcessInfo:processInfo():processName()
local quit_title = "Quit " .. app_name
quit_menu_item = NSMenuItem:alloc():initWithTitle_action_keyEquivalent_(quit_title, "terminate:", "q")
app_menu:addItem_(quit_menu_item)
app_menu_item:setSubmenu_(app_menu)
local main_window = NSWindow:alloc():initWithContentRect_styleMask_backing_defer_(NSMakeRect(0, 0, 200, 200), NSTitledWindowMask, NSBackingStoreBuffered, false)
main_window:cascadeTopLeftFromPoint_(NSMakePoint(20,20))
main_window:setTitle_(app_name)
main_window:makeKeyAndOrderFront_(nil)
NSApp:activateIgnoringOtherApps_(true)
NSApp:run()



