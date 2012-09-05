LuaCocoa.import("Foundation")
LuaCocoa.import("CoreGraphics", "/System/Library/Frameworks/ApplicationServices.framework/Frameworks")
LuaCocoa.import("QuartzCore")

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

function OnAction1(the_sender)
	print("OnAction1", the_sender)
	local my_rect = NSRect(1,2,3,4)
	print(my_rect)
	my_rect.size.width = 5
	print(my_rect)
	assert(my_rect.size.width == 5)
end

function OnAction2(the_sender)
	print("OnAction2", the_sender)
	local my_rect = NSRect(1,2,3,4)
	print(my_rect)
	local sub_size = my_rect.size
	sub_size.width = 6
	print(sub_size)
	assert(sub_size.width==6)
	print(my_rect)
	assert(my_rect.size.width == 6)
	my_rect = nil
	collectgarbage()
	print(sub_size)
	sub_size.width = 7
	collectgarbage()
	print(sub_size)
	sub_size = nil
	collectgarbage()
end


function OnAction3(the_sender)
	print("OnAction3", the_sender)
	local my_rect = NSRect(1,2,3,4)
	local my_rect2 = NSRect(5,6,7,8)
	print(my_rect)
	print(my_rect2)

	local sub_size = my_rect.size
	sub_size.width = 9
	print(sub_size)
	assert(sub_size.width==9)
	print(my_rect)
	assert(my_rect.size.width == 9)
	my_rect2.size = sub_size
	print(my_rect2)
	assert(my_rect2.size.width == 9)
	sub_size.width = 10
	print(my_rect)
	assert(my_rect.size.width == 10)	
	print(my_rect2)
	assert(my_rect2.size.width == 9)

	my_rect2.size.width=100
	print(my_rect2)
	assert(my_rect2.size.width == 100)
	print(my_rect)
	assert(my_rect.size.width == 10)

end


function OnAction4(the_sender)
	print("OnAction4", the_sender)

	local cgrect = CGRect(1,2,3,4)
	collectgarbage()
	local starttime = CACurrentMediaTime()
	-- On my iMac i3, the caching helps drop this from about 9 seconds to 3.5 seconds.
	-- This does not count the garbage collection time which is also significant since 100K's of objects are avoided from being created.
	for i=1, 100000 do
		cgrect.size.width = cgrect.size.width+1
		cgrect.size.height = cgrect.size.height+1
		cgrect.origin.y = cgrect.origin.y+1
		cgrect.origin.x = cgrect.origin.x+1
		
	end
	local endtime = CACurrentMediaTime()
	print("diff:", endtime-starttime)
	print(cgrect)
	cgrect = nil
	collectgarbage()
end

function OnAction5(the_sender)
	print("OnAction5", the_sender)
	local cgrect = CGRect(1,2,3,4)

	cgrect.size.width = 1
	cgrect.size.width = 2

	print(cgrect)
	cgrect = nil
	collectgarbage()

end


function OnAction6(the_sender)
	print("OnAction6", the_sender)

		

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

end


