LuaCocoa.import("Foundation")
LuaCocoa.import("CoreGraphics", "/System/Library/Frameworks/ApplicationServices.framework/Frameworks")


-- Note: If you modify this file while the application is running 
-- (which is in the .app bundle currently), 
-- Leopard FSEvents will notify the application
-- that this file has been changed and I reload the script.
-- You can do any special handling you need to do here.
function OnUnloadBeforeReload()
	print("OnUnloadBeforeReload")
end

function OnLoadFinished()
	print("OnLoadFinished")
end


function GlobalEnumerationBlock(id_obj, int_index, boolptr_stop) 
	print("in GlobalEnumerationBlock callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
	return false
end

function OnAction1(the_sender)
	print("OnAction1", the_sender)

	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})
	
	-- Basic test with anonymous function
	array:enumerateObjectsUsingBlock_(function(id_obj, int_index, boolptr_stop) 
		print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		-- this should do nothing
		boolptr_stop=true
--		return false
		end
	)
	
	
	collectgarbage()
end

function OnAction2(the_sender)
	print("OnAction2", the_sender)

	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})
	
	-- Basic test with global function
	array:enumerateObjectsUsingBlock_(GlobalEnumerationBlock)
	collectgarbage()
end


function OnAction3(the_sender)
	print("OnAction3", the_sender)
	
	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})

	-- Stop on "fee"
	array:enumerateObjectsUsingBlock_(function(id_obj, int_index, boolptr_stop) 
		print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		if tostring(id_obj) == "foo" then
			return true
		else
			return false
		end
	end
	)
	collectgarbage()
end


function OnAction4(the_sender)
	print("OnAction4", the_sender)

	local array = LuaCocoa.toCocoa({"bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz",  })
	-- test concurrent option. I seem to have a deadlocking bug. This doesn't work.
	array:enumerateObjectsWithOptions_usingBlock_(NSEnumerationConcurrent, function(id_obj, int_index, boolptr_stop) 
		print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		end
	)
	collectgarbage()
end

function OnAction5(the_sender)
	print("OnAction5", the_sender)

	-- test background thread
--	local array = MySpecialArray:alloc():initWithArray_({"bar", "foo", "fee"})
local array = LuaCocoa.toCocoa({"bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz", "bar", "foo", "fee", "baz",  })
	array:enumerateObjectsUsingBlock_(
		function(id_obj, int_index, boolptr_stop) 
			print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		end
	)

	collectgarbage()
	array:enumerateObjectsUsingBlock_(GlobalEnumerationBlock)
	collectgarbage()

end


function OnAction6(the_sender)
	print("OnAction6", the_sender)
	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})

	local new_block = LuaCocoa.toblock(
		function(id_obj, int_index, boolptr_stop) 
			print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		end,
		[[<arg>
<arg type='@'/>
<arg type64='Q' type='I'/>
<arg type='^B'/>
<retval type='v'/>
</arg>
]]
	)
	
	array:enumerateObjectsUsingBlock_(new_block)

	new_block = nil
	collectgarbage()
	
end


GlobalPremadeBlockFromAnonymousFunction = LuaCocoa.toblock(
	function(id_obj, int_index, boolptr_stop) 
		print("in GlobalPremadeBlockFromAnonymousFunction callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
		return false
	end,
	[[<arg> <arg type='@'/> <arg type64='Q' type='I'/> <arg type='^B'/> <retval type='v'/> </arg>]]
)

GlobalPremadeBlockFromGlobalFunction = LuaCocoa.toblock(
	GlobalEnumerationBlock,
	[[<arg> <arg type='@'/> <arg type64='Q' type='I'/> <arg type='^B'/> <retval type='v'/> </arg>]]
)

function OnAction7(the_sender)
	print("OnAction7", the_sender)

	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})
	array:enumerateObjectsUsingBlock_(GlobalPremadeBlockFromAnonymousFunction)
	collectgarbage()

	local array = LuaCocoa.toCocoa({"zip", "dee", "dah"})
	array:enumerateObjectsUsingBlock_(GlobalPremadeBlockFromAnonymousFunction)
	collectgarbage()

	local array = LuaCocoa.toCocoa({"bar", "foo", "fee"})
	array:enumerateObjectsUsingBlock_(GlobalPremadeBlockFromGlobalFunction)
	collectgarbage()

	local array = LuaCocoa.toCocoa({"zip", "dee", "dah"})
	array:enumerateObjectsUsingBlock_(GlobalPremadeBlockFromGlobalFunction)
	collectgarbage()
	
	
	local global_block_duplicate = LuaCocoa.toblock(
		GlobalEnumerationBlock,
		[[<arg> <arg type='@'/> <arg type64='Q' type='I'/> <arg type='^B'/> <retval type='v'/> </arg>]]
	)
	assert(global_block_duplicate == GlobalPremadeBlockFromGlobalFunction)

end

function OnAction8(the_sender)
	print("OnAction8", the_sender)
	
	local the_anonymous = LuaCocoa.tofunction(GlobalPremadeBlockFromAnonymousFunction)
	print(type(the_anonymous))
	assert(type(the_anonymous) == "function")
	the_anonymous(GlobalPremadeBlockFromAnonymousFunction, 1, nil)

	local the_global = LuaCocoa.tofunction(GlobalPremadeBlockFromGlobalFunction)
	assert(type(the_global) == "function")
	assert(the_global == GlobalEnumerationBlock)
	the_global(GlobalPremadeBlockFromGlobalFunction, 1, nil)

	-- Make sure LuaCocoa.toLua is now doing the same thing
	local the_anonymous2 = LuaCocoa.toLua(GlobalPremadeBlockFromAnonymousFunction)
	assert(the_anonymous == the_anonymous2)

	local the_global2 = LuaCocoa.toLua(GlobalPremadeBlockFromGlobalFunction)
	assert(the_global == the_global2)

end

function OnAction9(obj_block)
	print("OnAction9", obj_block)
	-- This is an Obj-C block. This should return nil
	local lua_function = LuaCocoa.tofunction(obj_block)
	assert(lua_function == nil)

	-- Make sure LuaCocoa.toLua is now doing the same thing	
	local lua_function2 = LuaCocoa.toLua(obj_block)
	assert(lua_function2 == nil)
	
	LuaCocoa.setBlockSignature(obj_block, [[<arg> <arg type='@'/> <arg type64='Q' type='I'/> <retval type='B'/> </arg>]])
	obj_block(obj_block, 5)
	local retflag = obj_block(obj_block, 5)
	assert(retflag == true)

	GlobalPremadeBlockFromAnonymousFunction(GlobalPremadeBlockFromAnonymousFunction, 0, nil)
	
end


--[=[
	local struct_return_block = LuaCocoa.toblock(
		function(id_obj) 
			print("in struct_return_block callback", id_obj)
			return id_obj
		end,
		[[<arg> <arg type64='{CGPoint=dd}' type='{CGPoint=ff}'/> <retval type64='{CGPoint=dd}' type='{CGPoint=ff}'/> </arg>]]
	)

--]=]

	local struct_return_block = LuaCocoa.toblock(
		function(id_obj) 
--			print("in struct_return_block callback", id_obj)
--			local new_rect = CGRect(5,6,7,8)
--print("new_rect", new_rect)
--			return new_rect
			return id_obj
--			return true
		end,
[[<arg> <arg type64='{CGRect=dddd}' type='{CGRect=ffff}'/> <retval type64='{CGRect=dddd}' type='{CGRect=ffff}'/> </arg>]]
--		[[<arg> <arg type64='{CGRect=dddd}' type='{CGRect=ffff}'/> <retval type='B'/> </arg>]]
	)

function OnAction10(the_sender)
	print("OnAction10", the_sender)

	print("calling")
	local ret_struct = struct_return_block(the_sender)
	print("returned")
	print("ret_struct", ret_struct)

	collectgarbage()
end

function OnAction11(obj_block)
	print("OnAction11", obj_block)

	LuaCocoa.setBlockSignature(obj_block, [[<arg> <arg type64='{CGRect=dd}' type='{CGRect=ff}'/> <arg type64='{CGRect=dd}' type='{CGRect=ff}'/> <retval type64='{CGRect=dddd}' type='{CGRect=ffff}'/> </arg>]])
	local cgpoint = CGPoint(10, 11)
	local cgsize = CGSize(12, 13)
	local cgrect = obj_block(cgpoint, cgsize)

	print(cgrect)
end


function OnAction12(obj_block)
	print("OnAction12", obj_block)


end
