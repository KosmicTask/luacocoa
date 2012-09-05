
print("Starting test.lua")

--LuaCocoa.import("CoreFoundation")
LuaCocoa.import("Foundation")

-- [=====[
LuaCocoa.import("CoreGraphics", "/System/Library/Frameworks/ApplicationServices.framework/Frameworks")
LuaCocoa.import("AppKit")
LuaCocoa.import("QuartzCore")

print("in lua, package.path", package.path)
--package.path = package.path .. ";/Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Resources/?.lua"
--print("in lua, package.path", package.path)

--require("string")

--require("re")
--require("olua")
-- [===[

print("<enum name='NSIntegerMax' value64='9223372036854775807' value='2147483647'> is:", NSIntegerMax)
print("<enum name='NSIntegerMin' value64='-9223372036854775808' value='-2147483648'> is:", NSIntegerMin)

print("<enum name='NSFoundationVersionNumber10_5_3' value='677.19'> is:", NSFoundationVersionNumber10_5_3)

print("<enum name='NSAppKitVersionNumber10_5_3' value='949.33000000000004'> is:", NSAppKitVersionNumber10_5_3)

print("<enum name='NSAlternateKeyMask' value='524288'> is:", NSAlternateKeyMask)
print("<enum name='NSAlertAlternateReturn' value='0'> is:", NSAlertAlternateReturn)

print("<constant name='NSFileHFSTypeCode' declared_type='NSString*' const='true' type='@'/> is:", NSFileHFSTypeCode)

print("<string_constant name='kSCNetworkConnectionBytesIn' nsstring='true' value='BytesIn'/> is: ", kSCNetworkConnectionBytesIn)



--print(ffi_doit)
--ffi_doit("<function name='NSBeep'/>")

print("ffi_prep_cif function", LuaCocoa.ffi_prep_cif)
cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif("<function name='NSBeep'/>")
print("cif, bridge_support_extra_data", cif, bridge_support_extra_data)

print("LuaCocoa.ffi_call function", LuaCocoa.ffi_call)
LuaCocoa.ffi_call(cif, bridge_support_extra_data)

cif = nil
bridge_support_extra_data = nil

print("Collecting Garbage")
collectgarbage()

--[[
print("ffi_prep_cif function", LuaCocoa.ffi_prep_cif)
cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif("<function name='NSSwapShort' inline='true'> <arg type='S'/> <retval type='S'/> </function>")
print("cif, bridge_support_extra_data", cif, bridge_support_extra_data)

print("LuaCocoa.ffi_call function", LuaCocoa.ffi_call)
ret_val = LuaCocoa.ffi_call(cif, bridge_support_extra_data, 65535)

print("swap value", ret_val)
--]]

cif = nil
bridge_support_extra_data = nil

print("Collecting Garbage")
collectgarbage()

print("NSSwapShort function", NSSwapShort)

--[[
function LuaCocoa.GenerateFunctionFromXML(xml_string)
	local cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif(xml_string)
	local return_function = function(...)
		return LuaCocoa.ffi_call(cif, bridge_support_extra_data, ...)
	end
	return return_function
end
--]]

collectgarbage()

--NSSwapShort = LuaCocoa.GenerateFunctionFromXML("<function name='NSSwapShort' inline='true'> <arg type='S'/> <retval type='S'/> </function>")
collectgarbage()

print("NSSwapShort(12345)", NSSwapShort(12345))

--assert(14640 == NSSwapShort(12345))

collectgarbage()

print("NSSwapShort(54321)", NSSwapShort(54321))
--assert(12756 == NSSwapShort(54321))

print("NSSwapShort(65280)", NSSwapShort(65280))
--assert(255 == NSSwapShort(65280))

print("NSSwapShort(255)", NSSwapShort(255))
--assert(65280 == NSSwapShort(255))

collectgarbage()


print("Starting Struct test")
ns_point = NSMakePoint(100, 200)
print("NSPoint", ns_point)

print("NSPoint[1]", ns_point[1])
print("NSPoint[2]", ns_point[2])

print("NSPoint.x, NSPoint.y", ns_point.x, ns_point.y)


ns_rect = NSMakeRect(300, 400, 500, 600)
print("NSRect", ns_rect)

return_point = ns_rect.origin
print("return_point", return_point)

return_size = ns_rect.size

print("return_point.x", return_point.x)

print("NSRect.origin, NSRect.size", return_point, return_size)
print("return_point[1] and [2], return_size[1] and [2]", return_point[1], return_point[2], return_size[1], return_size[2])
print("return_point.x and y, return_size.width and height", return_point.x, return_point.y, return_size.width, return_size.height)

print("ns_rect.origin.x and y, ns_rect.size.width and height", ns_rect.origin.x, ns_rect.origin.y, ns_rect.size.width, ns_rect.size.height)


print("set return_point.x = 350.0, y=450.0")
return_point.x = 350.0
return_point.y = 450.0

print("return_point.x, 2", return_point.x, return_point[2])

print("assigning: ns_point = return_point")
ns_point = return_point
print("ns_point[1], y", ns_point[1], ns_point.y)


print("Testing table coercion in Struct setter")
ns_rect.origin = {1000, 2000}
print("Changed ns_rect.origin with table ns_rect.origin = {1000, 2000}", ns_rect)

ns_rect.size = {height=4000, width=3000}
print("Changed ns_rect.size with table ns_rect.size = {height=4000, width=3000}", ns_rect)

--print("starting bad copy")
--ns_rect.origin = return_size
--print(ns_rect)

print("Testing table coercion in Struct __call")
ns_point({9.0, 10.0})
print("ns_point({9.0, 10.0})", ns_point)


ns_rect({ {1001, 2002}, {3003, 4004}})
print("ns_rect({ {1001, 2002}, {3003, 4004}})", ns_rect)

ns_rect({ 1011, 2022, 3033, 4044})
print("ns_rect({ 1011, 2022, 3033, 4044})", ns_rect)

ns_rect(1111, 2222, 3333, 4444)
print("ns_rect(1111, 2222, 3333, 4444)", ns_rect)

ns_rect({1110, 2220}, {3330, 4440})
print("ns_rect({1110, 2220}, {3330, 4440})", ns_rect)

ns_rect({x=1010, y=2020}, {width=3030, height=4040})
print("ns_rect({x=1010, y=2020}, {width=3030, height=4040})", ns_rect)


ns_rect({x=0010, [2]=0020}, {[1]=0030, height=0040})
print("ns_rect({x=0010, [2]=0020}, {[1]=0030, height=0040})", ns_rect)

ns_rect({origin = {x=10101, y=20202}, size = {width=30303, height=40404}})
print("ns_rect({origin = {x=10101, y=20202}, size = {width=30303, height=40404}})", ns_rect)


ns_rect({origin = {[1]=10111, [2]=20222}, [2] = {width=30333, height=40444}})
print("ns_rect({origin = {[1]=10111, [2]=20222}, [2] = {width=30333, height=40444}})", ns_rect)


print("Testing Struct Constructors")
print("NSPoint should be a function", NSPoint)
local my_new_point = NSPoint({11.0, 12.0})
print("my_new_point = NSPoint({11.0, 12.0})", my_new_point)


print("NSRect should be a function", NSRect)
local my_new_rect = NSRect({origin = {[1]=11111, [2]=22222}, [2] = {width=33333, height=44444}})
print("my_new_rect = NSRect({origin = {[1]=11111, [2]=22222}, [2] = {width=33333, height=44444}})", my_new_rect)

print("NSSize should be a function", NSSize)
local my_new_size = NSSize()
print("my_new_size = NSSize()", my_new_size)

print("test struct changes")
my_new_rect.size = my_new_size
my_new_size.width = 1000.0
print("rect and size", my_new_rect, my_new_size)

print("lpeg")

--print(lpeg.match(lpeg.P("variadic='true'"), "<function name='NSLog' variadic='true'>"))
print(string.match("<function name='NSLog' variadic='true'>", "variadic='true'"))
print("NSLog", NSLog)
NSLog("crap")
NSLog("Testing NSLog: string:%s", "a_string")
NSLog("Testing NSLog: float:%f", 1.0)
NSLog("Testing NSLog: double:%lf", 2.0)
NSLog("Testing NSLog: int:%d", 3)
NSLog("Testing NSLog: bool:%d", true)

print("Class testing")
print("Class NSString", NSString)
print("Class NSString:description", NSString:description())

print("Class NSProtocolChecker", NSProtocolChecker)

hello_string = NSString:alloc():initWithUTF8String("Hello World")
print("Printing returned NSString:", hello_string)
goodnight_string = NSString:alloc():initWithUTF8String("Goodnight World")
print("Printing returned NSString:", hello_string)
--NSString:alloc()
--foo = NSString["mykey"]
--foo = NSString[1]

local concat_string1 = hello_string .. goodnight_string
print("concat_string1:", concat_string1, "type:", type(concat_string1))
print("concat combo:", hello_string .. " a lua string")
local lua_string = tostring(concat_string1)
print("lua_string:", lua_string, "type:", type(lua_string))


local c_str = hello_string:UTF8String()
print("testing const char* via UTF8String ", c_str)


--[[
collectgarbage()
do
	local temp_string = NSString:alloc():initWithUTF8String("short lived string")
	print("looking for temp_string in weak_table", temp_string:description())

	local registry_table = debug.getregistry()
	local weak_table = registry_table["LuaCocoa.GlobalWeakTable"]
	for k, v in pairs(weak_table) do
		print(k, v)
	end


end

collectgarbage()

do
	print("After collectgarbage")
	local registry_table = debug.getregistry()
	local weak_table = registry_table["LuaCocoa.GlobalWeakTable"]
	for k, v in pairs(weak_table) do
		print(k, v)
	end
end
--]]

local dictionary = NSMutableDictionary:alloc():init()
dictionary:setObject_forKey_(goodnight_string, hello_string)
print("passed setObject_forKey_")
print("Dictionary[hello_string]", dictionary[hello_string])

print("Trying __newindex on dictionary")
dictionary[goodnight_string] = hello_string
dictionary["something_new"] = "A new string"

print("dictionary description:", dictionary:description())
print("dictionary #length:", #dictionary)

array = NSMutableArray:alloc():init()
print("Trying __newindex on array")
array[1] = hello_string
array[2] = NSNull:null()
array[3] = goodnight_string
print("array description:", array:description())
print("array #length:", #array)
print("end array")

print("NSZeroPoint", NSZeroPoint)
print("NSDebugEnabled", NSDebugEnabled)
print("NSDefaultRunLoopMode", NSDefaultRunLoopMode)

print("Testing dot notation setter")
print("CALayer", CALayer)
local ca_layer = CALayer:alloc():init()
print("ca_layer", ca_layer)

print("ca_layer description", ca_layer)
ca_layer.name = "My Layer Name"
print("Testing dot notation getter with __call hack")
print("ca_layer name:", ca_layer.name)
print("ca_layer name:", ca_layer:name())
print("ca_layer name:", ca_layer.name(ca_layer))


--local number_formater = NSNumberFormatter:alloc():init()
--print("number_formater:decimalSeparator()", number_formater:decimalSeparator())
--print("number_formater.decimalSeparator", number_formater.decimalSeparator)


-- NSFileManager fileExistsAtPath:isDirectory: is an interesting test because it returns a bool and has a bool out argument
print("testing out pointer and boolean")
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/System/Library/Frameworks", nil))
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/System/Library/Frameworks", false))
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/usr/bin/say", false))
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/notthere", true))
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/notthere", false))
local is_dir = true
print("NSFileManager_test:", NSFileManager:defaultManager():fileExistsAtPath_isDirectory_("/notthere", is_dir))

print("NSFileManager:defaultManager():contentsOfDirectoryAtPath_error_(\"/Users\", nil)", NSFileManager:defaultManager():contentsOfDirectoryAtPath_error_("/Users", nil))
local dir_list, the_error = NSFileManager:defaultManager():contentsOfDirectoryAtPath_error_("/notthere", true)
print("the_error", the_error)
print("dir_list", type(dir_list))

local object1_string = NSString:alloc():initWithUTF8String("Object1 for array")
local object2_string = NSString:alloc():initWithUTF8String("Object2 for array")

print("Testing Variadic methods with NSArray arrayWithObjects")
local variadic_array = NSArray:alloc():initWithObjects_(object1_string, object2_string, nil)
print("variadic_array", variadic_array)
local variadic_array = NSArray:arrayWithObjects_(object2_string, object1_string, object2_string, nil)
print("variadic_array", variadic_array)

-- [[
print("NSDivideRect")
local in_rect = NSRect(100, 100, 100, 100)
local out_rect = NSRect(1000, 1000, 1000, 1000)
local rem_rect = NSRect(2000, 2000, 2000, 2000)
print("Before", in_rect, out_rect, rem_rect)
new_out_rect, new_rem_rect = NSDivideRect(in_rect, out_rect, rem_rect, 50, NSMinYEdge)
print("after", in_rect, out_rect, rem_rect)
print("new_out_rect, new_rem_rect", new_out_rect, new_rem_rect)
new_out_rect()
new_rem_rect()

print("in_rect", in_rect)
print("out_rect, rem_rect", out_rect, rem_rect)
print("new_out_rect, new_rem_rect", new_out_rect, new_rem_rect)


--]]

local my_fake_selector = LuaCocoa.toselector("initWithFakeValue1:andFakeValue2:")
print("Fake selector", my_fake_selector)

print("CoreFoundation stuff")
print("kCFDateFormatterAMSymbol", kCFDateFormatterAMSymbol)
print("kCFAllocatorDefault", kCFAllocatorDefault)

local cf_string_hello = CFStringCreateWithCString(kCFAllocatorDefault, "Hello", kCFStringEncodingUTF8);
local cf_string_world = CFStringCreateWithCString(nil, " World", kCFStringEncodingUTF8);
print("cf_string_hello cf_string_world", cf_string_hello, cf_string_world)
local cf_mutable_string = CFStringCreateMutable(nil, 128);
CFStringAppend(cf_mutable_string, cf_string_hello)
CFStringAppend(cf_mutable_string, cf_string_world)
print("cf_mutable_string", cf_mutable_string)

--]===]

--]=====]
print("Subclass test")
do 
	new_class = LuaCocoa.CreateClass("MyLuaClass", NSClassFromString("MyBasicObject"))
--	new_class = LuaCocoa.CreateClass("MyLuaClass", NSNumberFormatter)
--	new_class = NSNumberFormatter

	print("new_class", new_class)
	
--		new_class["doSomething"] = 
		new_class["decimalSeparator"] = 
--		function (self) print("in new_class decimalSeparator") return "__sep_sep__"; end
--		function (self) print("in new_class for decimalSeparator"); local ret_val = self:super(NSNumberFormatter):decimalSeparator(); ret_val = "==" .. ret_val .. "=="; print("ret_val is", ret_val); return ret_val; end
	{
		function (self) print("in new_class for decimalSeparator"); local ret_val = self:super(NSClassFromString("MyBasicObject")):decimalSeparator(); ret_val = "==" .. ret_val .. "=="; print("ret_val is", ret_val); return ret_val; end,
		"-@@:"
	}
--]]

	print("alloc:init")

	local number_formater = new_class:alloc():init()
--	local number_formater = new_class:basicObject()

print("going to test calling number_formater:decimalSeparator()")
print("on object number_formater", number_formater)

--print("number_formater:decimalSeparator()", number_formater:doSomething())
print("number_formater:decimalSeparator()", number_formater:decimalSeparator())

	number_formater.__ivars.firstVar = "firstVar"
	print("number_formater.__ivars.firstVar", number_formater["__ivars"].firstVar)
	
	local number_formater_instance2 = new_class:alloc():init()
print("number_formater2", number_formater_instance2)

--[[
	local new_string_class = LuaCocoa.CreateClass("MyLuaSubStringClass", NSString)
	local lua_string_instance = new_string_class:alloc()
	print("lua_string_instance", lua_string_instance)
	lua_string_instance = lua_string_instance:init()
	print("lua_string_instance", lua_string_instance)
	
	local new_layer_class = LuaCocoa.CreateClass("MyLuaSubLayerClass", CALayer)
	local lua_layer_instance = new_layer_class:alloc()
	print("lua_layer_instance", lua_layer_instance)
	lua_layer_instance = lua_layer_instance:init()
	print("lua_string_instance", lua_layer_instance)
--]]
--[[
do
	number_formater = nil
	number_formater_instance2 = nil
--	lua_string_instance = nil
--	lua_layer_instance = nil
	collectgarbage()
	return
end
--]]

print("will this work?")
print("number_formater.decimalSeparator", number_formater.decimalSeparator)
print("number_formater.someInteger", number_formater.someInteger)


	local new_class_sub = LuaCocoa.CreateClass("MyLuaSubClass", "MyLuaClass")
--	new_class["doSomething"] = function () print("ran doSomething") end

-- [[
	new_class["init"] = 
	{
		function (self) 
			print("in new_class init"); 
				local super_self = self:super(NSClassFromString("MyBasicObject"))
--			print("got super_self", super_self);
			print("got super_self");
			self = super_self:init() 
			print("got init self", self);
			return self 
		end,
		"-@@:"
	}
	--]]
--	print("function is", new_class["doSomething"])



	new_class_sub["init"] = 
	{
		function (self) 
			print("in new_class_sub init");
			local super_self = self:super(new_class)
			print("got super_self", super_self);
			self = super_self:init() 
			print("got init self", self);
			return self 
		end,
		"-@@:"
	}
	
	--[[
do
	number_formater = nil
	number_formater_instance2 = nil
--	lua_string_instance = nil
--	lua_layer_instance = nil
	collectgarbage()
	return
end
--]]

	do
		local new_instance = new_class:alloc():init()
		print("new instance", new_instance)

--[[
do
	number_formater = nil
	new_instance = nil
		number_formater_instance2 = nil

	collectgarbage()
	print("early escape")
	return
end
--]]


		local new_instance_sub = new_class_sub:alloc():init()
		print("new_instance_sub", new_instance_sub)


		new_instance:doSomething()
		print("trying doSomething() inheritence");
--		new_instance_sub:doSomething()
--				print("trying doSomething() inheritence2");


-- [[

--]]
-- [[
	new_class_sub["decimalSeparator"] = 
	{
		function (self) print("in new_class_sub decimalSeparator"); return self:super(new_class):decimalSeparator() end,
		"-@@:"
	}
--]]

print("new_instance_sub:decimalSeparator()", new_instance_sub:decimalSeparator())

--[[
do
	number_formater = nil
	new_instance = nil
		number_formater_instance2 = nil
new_instance_sub = nil
	collectgarbage()
	print("early escape")
	return
end
--]]


			new_class_sub["doSomething"] = 
			{
				"-v@:",
				function (self) 
					print("in subclass doSomething"); 
					self:super(new_class):doSomething()
	--				print("got super", the_super)
	--				the_super:doSomething()
					print("self", self)
					local the_description = self:description()
					print("the_description", the_description)
					print("self:decimalSeparator()", self:decimalSeparator())

					--self:doSomething() 
				end
			}
	print("sub function is", new_class_sub["doSomething"])
	
		print("testing parent", new_class["doSomething"])

		new_instance:doSomething()

		print("testing sub", new_class_sub["doSomething"])
		new_instance_sub:doSomething()
		
			local new_class_sub2 = LuaCocoa.CreateClass("MyLuaSubClass2", "MyLuaSubClass")
			local new_class_sub3 = LuaCocoa.CreateClass("MyLuaSubClass3", "MyLuaSubClass2")
		local new_instance_sub3 = new_class_sub3:alloc():init()
		print("testing sub3", new_class_sub["doSomething"])
		new_instance_sub3:doSomething()


			new_class["doSomething2"] = 
			{ function (self) 
				print("in subclass doSomething2")
			end,
			"-v@:"
			}
			
			new_class["doSomething3withaBool_aDouble_anInteger_aString_anId_"] = 
			{ function (self, a_bool, a_double, an_integer, a_string, an_id) 
				print("in subclass doSomething3, arglist:", self, a_bool, a_double, an_integer, a_string, an_id)
				local ret_string = NSString:stringWithUTF8String_(a_string)
				print("ret string is", ret_string)
				print("ret string description is", ret_string:description())
				return ret_string
			end,
			"-@@:Bdi*@"
			}

			new_class["doSomething4withPointer_"] = 
			{ function (self, a_pointer)
			print("doSomething4withPointer_")
				self:super(NSClassFromString("MyBasicObject")):doSomething4withPointer_(a_pointer)
			end,
			"-v@:^v"
			}

			-- Moving to Lion/non-Fullbridgesupport introduced a bug with selectors because the bridgesupport data format is different
			new_class["someMethodToInvokeViaSelector"] =
			{
				"-@@:",
				function (self)
					print("In someMethodToInvokeViaSelector")
					return nil
				end
			}

			local the_selector = LuaCocoa.toselector("someMethodToInvokeViaSelector")
			if new_instance_sub3:respondsToSelector_(the_selector) then
				print("respondsToSelector passed")
			else
				print("respondsToSelector failed")
				assert(false)
			end
			new_instance_sub3:performSelector_(the_selector)
			
		new_instance_sub3 = nil
		new_instance_sub = nil
		new_instance = nil
		
		number_formater = nil
		number_formater_instance2 = nil

	end

	collectgarbage()
	
end
collectgarbage()



--print("trying Objective-Lua")
--[[
local intext = io.open(("/Users/ewing/Source/HG/LuaCocoa/Test/test_objectivelua.olua")):read("*a")
local outtext = olua.translate(intext)
print(outtext)
--]]

--require("test_objectivelua")

print("End subclass test")
print("Ending test.lua")

