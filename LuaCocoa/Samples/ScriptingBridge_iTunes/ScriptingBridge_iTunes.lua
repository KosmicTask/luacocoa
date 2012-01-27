#!/Library/Frameworks/LuaCocoa.framework/Versions/Current/Tools/luacocoa
--[[
Simple Scripting Bridge example using iTunes.
Script will launch iTunes (if not already open),
Pause playback (if not already paused),
Start/resume playing,
and print out the name, artist, year of the current track.
--]]

LuaCocoa.import("ScriptingBridge")

local itunes_application = SBApplication:applicationWithBundleIdentifier_("com.apple.iTunes")

if itunes_application ~= nil then

	print("Pausing iTunes")
	itunes_application:pause()
	print("Playing/Resuming iTunes")
	itunes_application:playpause()

	local itunes_track = itunes_application:currentTrack()
	NSLog("Currently playing: Name:%@, Artist:%@, Year:%d", 
	itunes_track:name(), 
		itunes_track:artist() 
		,itunes_track:year()
		)

else
	print("iTunes not available")
end


