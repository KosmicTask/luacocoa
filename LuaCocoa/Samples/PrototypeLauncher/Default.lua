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

function OnAction1(animatable_layer, app_delegate)
	print("OnAction1", animatable_layer)
end

function OnAction2(animatable_layer, app_delegate)
	print("OnAction2", animatable_layer)
end


function OnAction3(animatable_layer, app_delegate)
	print("OnAction3", animatable_layer)
end


function OnAction4(animatable_layer, app_delegate)
	print("OnAction4", animatable_layer)
end

function OnAction5(animatable_layer, app_delegate)
	print("OnAction5", animatable_layer)
end

