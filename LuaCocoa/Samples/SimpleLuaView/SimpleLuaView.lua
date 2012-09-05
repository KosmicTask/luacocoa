LuaCocoa.import("Cocoa")

SimpleLuaView = nil

SimpleLuaView = LuaCocoa.CreateClass("SimpleLuaView", NSView)

SimpleLuaView["drawRect_"] = 
{
	-- TODO: Provide an API to get signatures for methods and types.
	-- Currently, if the method signature is already defined in Obj-C by the super-class,
	-- then I think it is okay if the signature is imperfect (so don't worry about 32-bit vs. 64-bit).
	"-v@:{CGRect={CGPoint=dd}{CGSize=dd}}",
	function (self, the_rect)
--		NSColor:whiteColor():set()
		NSColor:redColor():set()
--		print("bounds", self:bounds())
--		print("origin", self:bounds().origin)
--		print("size", self.bounds.size)
--		NSRectFill(self:bounds())
		NSRectFill(the_rect)
	end
}

------------------ The above is all you need.
------------------ Below shows off categories which is very similar to subclassing.
------------------ The following is unnecessary to the program.


NSView["rightMouseDown_"] =
{
	"-v@:@",
	function(self, the_event)
		NSLog("rightMouseDown_ %@", the_event)
	end
}

NSView["keyDown_"] =
{
	"-v@:@",
	function(self, the_event)
		NSLog("keyDown_ %@", the_event)
	end
}

NSResponder["keyUp_"] =
{
	"-v@:@",
	function(self, the_event)
		NSLog("keyUp_ %@", the_event)
	end
}

-- For contrast, this is our subclass
SimpleLuaView["mouseDown_"] =
{
	"-v@:@",
	function(self, the_event)
		NSLog("rightMouseDown_ %@", the_event)
	end
}

-- We can also access the SimpleLuaViewAppDelegate even though this file has nothing to do with it.
-- This will cause the program to exit when the window closes.
SimpleLuaViewAppDelegate["applicationShouldTerminateAfterLastWindowClosed_"] =
{
	"-B@:@",
	function(self, the_application)
		print("applicationShouldTerminateAfterLastWindowClosed_ ", self, the_application)
		return true
	end
}