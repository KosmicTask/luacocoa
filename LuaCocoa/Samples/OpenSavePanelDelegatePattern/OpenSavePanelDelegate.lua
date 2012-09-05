LuaCocoa.import("Cocoa")

function GetMainWindow()
	-- This will get the current main window. If you change focus, this value changes so it is unreliable.
	local mainwindow = NSApplication:sharedApplication():mainWindow()
	
	return mainwindow
end

SavePanelDelegate = nil

SavePanelDelegate = LuaCocoa.CreateClass("SavePanelDelegate", NSObject, "NSOpenSavePanelDelegate")

SavePanelDelegate["savePanelDidEnd_returnCode_contextInfo_"] = 
{
	-- TODO: Provide an API to get signatures for methods and types.
	-- Currently, if the method signature is already defined in Obj-C by the super-class,
	-- then I think it is okay if the signature is imperfect (so dont worry about 32-bit vs. 64-bit).
	"-v@:@i^v",
	function (self, panel, returncode, contextinfo)
		print("in SavePanelDelegate didEndCallback_")
		print(self, panel, returncode, contextinfo)
		-- release the delegate we retained
		self:autorelease()

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
}

function ShowSavePanel(thewindow)
		local savedelegate = SavePanelDelegate:alloc():init()
		-- savedelegate:savePanelDidEnd_returnCode_contextInfo_(savedelegate, 3, 2)
		-- kind of crappy design pattern, probably why Apple deprecated this.
		-- retain for safety because the sheet doesn't necessarily keep the delegate around and LuaCocoa will automatically release the object when it goes out of this scope.
		savedelegate:retain()
		local panel = NSSavePanel:savePanel()

		local theselector = LuaCocoa.toselector("savePanelDidEnd:returnCode:contextInfo:")
--		NSLog("delegate: %@, selector: %@", savedelegate, theselector)
--		print("delegate, selector ", savedelegate, theselector)
		local paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
		local default_dir = paths[1]
		panel:beginSheetForDirectory_file_modalForWindow_modalDelegate_didEndSelector_contextInfo_(default_dir, "foo.fee", thewindow, savedelegate, theselector, nil)

end



OpenPanelDelegate = nil

OpenPanelDelegate = LuaCocoa.CreateClass("OpenPanelDelegate", NSObject, "NSOpenSavePanelDelegate")

OpenPanelDelegate["openPanelDidEnd_returnCode_contextInfo_"] = 
{
	-- TODO: Provide an API to get signatures for methods and types.
	-- Currently, if the method signature is already defined in Obj-C by the super-class,
	-- then I think it is okay if the signature is imperfect (so dont worry about 32-bit vs. 64-bit).
	"-v@:@i^v",
	function (self, panel, returncode, contextinfo)
		print("in openPanelDidEnd_returnCode_contextInfo_")
		print(self, panel, returncode, contextinfo)
		-- release the delegate we retained
		self:autorelease()


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
}


function ShowOpenPanel(thewindow)
		local opendelegate = OpenPanelDelegate:alloc():init()
		-- kind of crappy design pattern, probably why Apple deprecated this.
		-- retain for safety because the sheet doesn't necessarily keep the delegate around and LuaCocoa will automatically release the object when it goes out of this scope.
		opendelegate:retain()

		local panel = NSOpenPanel:openPanel()

		-- Lots of little options like can choose directories and/or files, multiple selection,
		panel:setCanChooseDirectories_(true)
		panel:setCanChooseFiles_(true)
		panel:setAllowsMultipleSelection_(true)

		local theselector = LuaCocoa.toselector("openPanelDidEnd:returnCode:contextInfo:")

		local paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
		local default_dir = paths[1]


		panel:beginSheetForDirectory_file_types_modalForWindow_modalDelegate_didEndSelector_contextInfo_(default_dir, "foo.fee", { "fee", "foo", "png" }, mainwindow, opendelegate, theselector, nil)




end



function OpenDocument(thesender, thewindow)
	ShowOpenPanel(thewindow)
end



function SaveDocument(thesender, thewindow)
	ShowSavePanel(thewindow)
end
