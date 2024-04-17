//
//  Folder+Scriptability.swift
//  NetNewsWire
//
//  Created by Olof Hellman on 1/10/18.
//  Copyright © 2018 Olof Hellman. All rights reserved.
//

import Foundation
import Account
import Articles
import Core

@objc(ScriptableFolder)
@MainActor class ScriptableFolder: NSObject, UniqueIDScriptingObject, ScriptingObjectContainer {

    let folder:Folder
    let container:ScriptingObjectContainer

    init (_ folder:Folder, container:ScriptingObjectContainer) {
        self.folder = folder
        self.container = container
    }

    @objc(objectSpecifier)
    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
		MainActor.assumeIsolated {
			let scriptObjectSpecifier = self.container.makeFormUniqueIDScriptObjectSpecifier(forObject:self)
			return (scriptObjectSpecifier)
		}
    }

    // MARK: --- ScriptingObject protocol ---

    var scriptingKey: String {
        return "folders"
    }

    // MARK: --- UniqueIDScriptingObject protocol ---

    // I am not sure if account should prefer to be specified by name or by ID
    // but in either case it seems like the accountID would be used as the keydata, so I chose ID

    @objc(uniqueID)
    var scriptingUniqueID:Any {
        return folder.folderID
    }
    
    // MARK: --- ScriptingObjectContainer protocol ---
    
    var scriptingClassDescription: NSScriptClassDescription {
        return self.classDescription as! NSScriptClassDescription
    }
 
	@MainActor func deleteElement(_ element:ScriptingObject) {
		// TODO: fix this
//       if let scriptableFeed = element as? ScriptableFeed {
//            BatchUpdate.shared.perform {
//				folder.account?.removeFeed(scriptableFeed.feed, from: folder) { result in }
//            }
//        }
    }

    // MARK: --- handle NSCreateCommand ---
    /*
        handle an AppleScript like
           make new folder in account X with properties {name:"new folder name"}
        or
           tell account X to make new folder at end with properties {name:"new folder name"}
    */
	@MainActor class func handleCreateElement(command:NSCreateCommand) -> Any?  {
		guard command.isCreateCommand(forClass:"fold") else { return nil }
		let name = command.property(forKey:"name") as? String ?? ""

		// some combination of the tell target and the location specifier ("in" or "at")
		// identifies where the new folder should be created
		let (account, folder) = command.accountAndFolderForNewChild()
		guard folder == nil else {
			print("support for folders within folders is NYI");
			return nil
		}

		command.suspendExecution()

		Task { @MainActor in
			do {
				let folder = try await account.addFolder(name)
				let scriptableAccount = ScriptableAccount(account)
				let scriptableFolder = ScriptableFolder(folder, container:scriptableAccount)
				command.resumeExecution(withResult:scriptableFolder.objectSpecifier)
			} catch {
				command.resumeExecution(withResult:nil)
			}
		}

		return nil
	}

    // MARK: --- Scriptable elements ---
    
    @objc(feeds)
    var feeds:NSArray  {
		let feeds = Array(folder.topLevelFeeds)
        return feeds.map { ScriptableFeed($0, container:self) } as NSArray
    }

    // MARK: --- Scriptable properties ---
    
    @objc(name)
    var name:String  {
        return self.folder.name ?? ""
    }

    @objc(opmlRepresentation)
    var opmlRepresentation:String  {
        return self.folder.OPMLString(indentLevel:0)
    }

}
