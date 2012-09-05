LuaCocoa.import("Foundation")

g_undoManager = nil
g_myUndoProxy = nil
-- [[
MyUndoProxy = LuaCocoa.CreateClass("MyUndoProxy", NSObject)
MyUndoProxy["invokeGenericUndo_"] =
{
	"-v@:@",
	function(self, the_arg)
		print("in invokeGenericUndo_", the_arg)
		local is_undoing = g_undoManager:isUndoing()
		print("is_undoing", is_undoing)

		local the_selector = LuaCocoa.toselector("invokeGenericUndo:")
		
		g_undoManager:registerUndoWithTarget_selector_object_(self, the_selector, the_arg)



	end

}
--]]

-- Note: If you modify this file while the application is running 
-- (which is in the .app bundle currently), 
-- Leopard FSEvents will notify the application
-- that this file has been changed and I reload the script.
-- You can do any special handling you need to do here.
function OnUnloadBeforeReload()
	print("OnUnloadBeforeReload")
	if g_undoManager then
		g_undoManager:removeAllActions()
	end
	g_undoManager = nil
	g_myUndoProxy = nil
end

function OnLoadFinished()
	print("OnLoadFinished")
	g_myUndoProxy = MyUndoProxy:alloc():init()

	if not g_undoManager then
		g_undoManager = NSUndoManager:alloc():init()
	end
end

AppDelegate["windowWillReturnUndoManager_"] =
{
	"-@@:@",
	function(self, the_sender)
		print("windowWillReturnUndoManager_", self, the_sender)
		if not g_undoManager then
			g_undoManager = NSUndoManager:alloc():init()
		end

		return g_undoManager
	end
}
AppDelegate["applicationShouldTerminateAfterLastWindowClosed_"] =
{
	"-B@:@",
	function(self, the_application)
		print("applicationShouldTerminateAfterLastWindowClosed_ ", self, the_application)
		return true
	end
}
g_counter = 1
function OnAction1(the_sender)
	print("OnAction1", the_sender)
	local the_selector = LuaCocoa.toselector("invokeGenericUndo:")
	print(g_undoManager, g_myUndoProxy)
	g_undoManager:registerUndoWithTarget_selector_object_(g_myUndoProxy, the_selector, "Hello World" .. tostring(g_counter))
--[[
	local invoc = g_undoManager:prepareWithInvocationTarget_(g_myUndoProxy)
	NSLog("invoc %@", invoc)
	local the_value = NSString:stringWithUTF8String_("Hello World" .. tostring(g_counter))
	NSLog("the_value %@", the_value)

	print(invoc:target())
	print(invoc:selector())
	print(invoc:methodSignature())
--	invoc:performSelector_withObject(the_selector, the_value)
--	invoc:invokeGenericUndo_(the_value)
--]]
	if not g_undoManager:isUndoing() then
		g_undoManager:setActionName_(tostring(g_counter))
	end
	g_counter = g_counter + 1
end

function OnAction2(the_sender)
	print("OnAction2", the_sender)
end


function OnAction3(the_sender)
	print("OnAction3", the_sender)
end


function OnAction4(the_sender)
	print("OnAction4", the_sender)
end

function OnAction5(the_sender)
	print("OnAction5", the_sender)
end


