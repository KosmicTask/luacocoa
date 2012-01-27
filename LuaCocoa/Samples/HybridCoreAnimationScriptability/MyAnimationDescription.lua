LuaCocoa.import("QuartzCore")
LuaCocoa.import("Foundation")

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

function OnAnimationDidStop(animatable_layer, the_animation, reached_natural_end)
	print("OnAnimationDidStop", animatable_layer, the_animation, reached_natural_end)
end



function OnAction1(animatable_layer, app_delegate)
	print("OnAction1", animatable_layer)
	local keyframe_animation = CAKeyframeAnimation:animation()
	-- Demonstrating setter dot-notation here.
	-- Also, this is the formal Obj-C/Cocoa way to create an NSArray of structs
	-- See OnAction2 for a short-cut Lua/Cocoa way.
	keyframe_animation.values = 
		NSArray:arrayWithObjects_(
			NSValue:valueWithPoint_(
				NSMakePoint(0,0)
			),
			NSValue:valueWithPoint_(
				NSMakePoint(340, 280)
			),
			NSValue:valueWithPoint_(
				NSMakePoint(300, 200)
			),
			nil
		)
	-- I could write the delegate directly in Lua,
	-- but because I want to support unloading/reloading the entire Lua state,
	-- I need to be careful about dangling objects when Lua gets torn down 
	-- and an animation is still in flight and then finishes firing a 
	-- callback into a dead delegate.
	-- Using Obj-C garbage collection might avoid that messy case since 
	-- Obj-C is supposed to nil out dead references automatically. 
	-- I should try that some time.
	keyframe_animation.delegate = app_delegate
	animatable_layer.position = CGPointMake(300, 200)
	animatable_layer:addAnimation_forKey_(keyframe_animation, "position")
end

function OnAction2(animatable_layer, app_delegate)
	print("OnAction2", animatable_layer)
	local keyframe_animation = CAKeyframeAnimation:animation()
	-- Some shortcuts for LuaCocoa:
	-- Instead of explicitly creating a new NSArray, we can use a Lua table.
	-- Since we aren't using the arrayWithObjects method, we don't need to 
	-- worry about the nil-termination requirement.
	-- Instead of using the function NSMakePoint, LuaCocoa overloads the
	-- struct name to be a constructor function so if you pass it the
	-- paramters to fill the struct, it will fill it.
	-- Instead of boxing the structs in NSValues, we can let LuaCocoa do that.
	-- The way this works is that when we cross the bridge, the table gets
	-- converted/copied into an NSArray automatically via the topropertylist
	-- functions.
	keyframe_animation.values = {
		NSPoint(0,550),
		NSPoint(500, 250),
		NSPoint(200, 200)
	}
	-- I could write the delegate directly in Lua,
	-- but because I want to support unloading/reloading the entire Lua state,
	-- I need to be careful about dangling objects when Lua gets torn down 
	-- and an animation is still in flight and then finishes firing a 
	-- callback into a dead delegate.
	-- Using Obj-C garbage collection might avoid that messy case since 
	-- Obj-C is supposed to nil out dead references automatically. 
	-- I should try that some time.
	keyframe_animation.delegate = app_delegate
	keyframe_animation.duration = 2.5
	animatable_layer.position = CGPoint(200, 200)
	animatable_layer:addAnimation_forKey_(keyframe_animation, "position")
end


function OnAction3(animatable_layer, app_delegate)
	print("OnAction3", animatable_layer)
	local keyframe_animation = CAKeyframeAnimation:animation()
	keyframe_animation.values = {
		0,
		2*math.pi,
		-2 * math.pi,
		1 * math.pi
	}
	-- I could write the delegate directly in Lua,
	-- but because I want to support unloading/reloading the entire Lua state,
	-- I need to be careful about dangling objects when Lua gets torn down 
	-- and an animation is still in flight and then finishes firing a 
	-- callback into a dead delegate.
	-- Using Obj-C garbage collection might avoid that messy case since 
	-- Obj-C is supposed to nil out dead references automatically. 
	-- I should try that some time.
	keyframe_animation.delegate = app_delegate
	keyframe_animation.duration = 3.0
	animatable_layer:setValue_forKeyPath_(NSNumber:numberWithFloat_(math.pi), "transform.rotation.z")
	
	animatable_layer:addAnimation_forKey_(keyframe_animation, "transform.rotation.z")

end


function OnAction4(animatable_layer, app_delegate)
	print("OnAction4", animatable_layer)
	local keyframe_animation = CAKeyframeAnimation:animation()
	keyframe_animation.values = {
		1.0,
		0.1,
		1.0
	}
	-- I could write the delegate directly in Lua,
	-- but because I want to support unloading/reloading the entire Lua state,
	-- I need to be careful about dangling objects when Lua gets torn down 
	-- and an animation is still in flight and then finishes firing a 
	-- callback into a dead delegate.
	-- Using Obj-C garbage collection might avoid that messy case since 
	-- Obj-C is supposed to nil out dead references automatically. 
	-- I should try that some time.
	keyframe_animation.delegate = app_delegate
	keyframe_animation.duration = 2.0
	animatable_layer.opacity = 1.0
	animatable_layer:addAnimation_forKey_(keyframe_animation, "opacity")
end

function OnAction5(animatable_layer, app_delegate)
	print("OnAction5", animatable_layer)

	OnAction2(animatable_layer, app_delegate)
	OnAction3(animatable_layer, app_delegate)
	OnAction4(animatable_layer, app_delegate)

end

