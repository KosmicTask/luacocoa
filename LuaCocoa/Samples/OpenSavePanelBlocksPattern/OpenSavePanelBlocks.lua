LuaCocoa.import("Cocoa")

function GetMainWindow()
	-- This will get the current main window. If you change focus, this value changes so it is unreliable.
	local mainwindow = NSApplication:sharedApplication():mainWindow()
	
	return mainwindow
end

function ShowSavePanel(thewindow)
	local mainwindow = GetMainWindow()

	local panel = NSSavePanel:savePanel()

	local paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
	local default_dir = paths[1]
	local default_url = NSURL:fileURLWithPath_(default_dir)
	panel:setDirectoryURL_(default_url)
	panel:setNameFieldStringValue_("foo.fee")

	panel:beginSheetModalForWindow_completionHandler_(mainwindow, 
		-- This anonymous Lua function gets converted to an Obj-C block
		function(returncode)
			print("in SavePanelDelegate didEndCallback_")

			if returncode == NSFileHandlingPanelOKButton then
				print("User hit OK")
				print("URL ", panel:URL():path())
				print("directoryURL ", panel:directoryURL():path())
				print("nameFieldStringValue ", panel:nameFieldStringValue())

			elseif returncode == NSFileHandlingPanelCancelButton then
				print("User hit cancel")
			else
				print("This code shouldn't be possible")
			end
		end
	)

end





function ShowOpenPanel(thewindow)
	local mainwindow = GetMainWindow()

	local panel = NSOpenPanel:openPanel()

	-- Lots of little options like can choose directories and/or files, multiple selection
	panel:setCanChooseDirectories_(true)
	panel:setCanChooseFiles_(true)
	panel:setAllowsMultipleSelection_(true)

	local paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
	local default_dir = paths[1]
	local default_url = NSURL:fileURLWithPath_(default_dir)
	panel:setDirectoryURL_(default_url)

	panel:setAllowedFileTypes_({ "fee", "foo", "png" })


	panel:beginSheetModalForWindow_completionHandler_(mainwindow, 
		-- This anonymous Lua function gets converted to an Obj-C block
		function(returncode)
			if returncode == NSFileHandlingPanelOKButton then
				print("User hit OK")
				-- Panel allows for multiple selection so we get an array
				local array_of_urls = panel:URLs()
				NSLog("urls %@", array_of_urls)
				for i=1, #array_of_urls do
					local url = array_of_urls[i]
					print("URL path ", url:path())
					print("lastPathComponent ", url:lastPathComponent())
				end
			elseif returncode == NSFileHandlingPanelCancelButton then
				print("User hit cancel")
			else
				print("This code shouldn't be possible")
			end
		end
	)
end



function OpenDocument(thesender, thewindow)
	ShowOpenPanel(thewindow)
end



function SaveDocument(thesender, thewindow)
	ShowSavePanel(thewindow)
end
