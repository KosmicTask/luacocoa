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
