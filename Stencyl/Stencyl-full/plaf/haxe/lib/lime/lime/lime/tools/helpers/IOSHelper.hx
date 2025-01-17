package lime.tools.helpers;


import haxe.io.Path;
import lime.tools.helpers.PathHelper;
import lime.tools.helpers.ProcessHelper;
import lime.project.Haxelib;
import lime.project.HXProject;
import sys.io.Process;
import sys.FileSystem;


class IOSHelper {
	
	
	private static var initialized = false;
	
	
	public static function build (project:HXProject, workingDirectory:String, additionalArguments:Array <String> = null):Void {
		
		initialize (project);
		
		var platformName = "iphoneos";
		
		if (project.targetFlags.exists ("simulator")) {
			
			platformName = "iphonesimulator";
			
		}
		
		var configuration = "Release";
		
		if (project.debug) {
			
			configuration = "Debug";
			
		}
			
		var iphoneVersion = project.environment.get ("IPHONE_VER");
		var commands = [ "-configuration", configuration, "PLATFORM_NAME=" + platformName, "SDKROOT=" + platformName + iphoneVersion ];
			
		if (project.targetFlags.exists("simulator")) {
			
			commands.push ("-arch");
			commands.push ("i386");
			
		}
		
		if (additionalArguments != null) {
			
			commands = commands.concat (additionalArguments);
			
		}
		
		ProcessHelper.runCommand (workingDirectory, "xcodebuild", commands);
		
	}
	
	
	public static function getSDKDirectory (project:HXProject):String {
		
		initialize (project);
		
		var platformName = "iPhoneOS";
		
		if (project.targetFlags.exists ("simulator")) {
			
			platformName = "iPhoneSimulator";
			
		}
		
		var process = new Process ("xcode-select", [ "--print-path" ]);
		var directory = process.stdout.readLine ();
		process.close ();
		
		if (directory == "" || directory.indexOf ("Run xcode-select") > -1) {
			
			directory = "/Applications/Xcode.app/Contents/Developer";
			
		}
		
		directory += "/Platforms/" + platformName + ".platform/Developer/SDKs/" + platformName + project.environment.get ("IPHONE_VER") + ".sdk";
		return directory;
		
	}
	
	
	private static function getIOSVersion (project:HXProject):Void {
		
		if (!project.environment.exists("IPHONE_VER")) {
			if (!project.environment.exists("DEVELOPER_DIR")) {
				var proc = new Process("xcode-select", ["--print-path"]);
				var developer_dir = proc.stdout.readLine();
				proc.close();
				project.environment.set("DEVELOPER_DIR", developer_dir);
			}
			var dev_path = project.environment.get("DEVELOPER_DIR") + "/Platforms/iPhoneOS.platform/Developer/SDKs";
			
			if (FileSystem.exists (dev_path)) {
				var best = "";
				var files = FileSystem.readDirectory (dev_path);
				var extract_version = ~/^iPhoneOS(.*).sdk$/;
				
				for (file in files) {
					if (extract_version.match (file)) {
						var ver = extract_version.matched (1);
						if (ver > best)
							best = ver;
					}
				}
				
				if (best != "")
					project.environment.set ("IPHONE_VER", best);
			}
		}
		
	}
	
	
	private static function getOSXVersion ():String {
		
		var output = ProcessHelper.runProcess ("", "sw_vers", [ "-productVersion" ]);
		
		return StringTools.trim (output);
		
	}
	
	
	public static function getProvisioningFile ():String {
		
		var path = PathHelper.expand ("~/Library/MobileDevice/Provisioning Profiles");
		var files = FileSystem.readDirectory (path);
		
		for (file in files) {
			
			if (Path.extension (file) == "mobileprovision") {
				
				return path + "/" + file;
				
			}
			
		}
		
		return "";
		
	}
	
	
	private static function getXcodeVersion ():String {
		
		var output = ProcessHelper.runProcess ("", "xcodebuild", [ "-version" ]);
		var firstLine = output.split ("\n").shift ();
		
		return StringTools.trim (firstLine.substring ("Xcode".length, firstLine.length));
		
	}
	
	
	private static function initialize (project:HXProject):Void {
		
		if (!initialized) {
			
			getIOSVersion (project);
			
			initialized = true;
			
		}
		
	}
	
	
	public static function launch (project:HXProject, workingDirectory:String):Void {
		
		initialize (project);
		
		var configuration = "Release";
			
		if (project.debug) {
			
			configuration = "Debug";
			
		}
		
		if (project.targetFlags.exists ("simulator")) {
			
			var applicationPath = "";
			
			if (Path.extension (workingDirectory) == "app" || Path.extension (workingDirectory) == "ipa") {
				
				applicationPath = workingDirectory;
				
			} else {
				
				applicationPath = workingDirectory + "/build/" + configuration + "-iphonesimulator/" + project.app.file + ".app";
				
			}
			
			var family = "iphone";
			var tall = "";
			var retina = "";	
			var altCommand = false;
			
			if (project.targetFlags.exists ("ipad")) {
				
				family = "ipad";
				tall = "com.apple.CoreSimulator.SimDeviceType.iPad-2";
				altCommand = true;
			}

			if (project.targetFlags.exists ("retina")) 
			{
				if(project.targetFlags.exists ("ipad"))
				{
					tall = "com.apple.CoreSimulator.SimDeviceType.iPad-Air";
				}
				
				else
				{
					tall = "com.apple.CoreSimulator.SimDeviceType.iPhone-4s";
					altCommand = true;
				}
			}
			
			if (project.targetFlags.exists ("tall")) {
				tall = "com.apple.CoreSimulator.SimDeviceType.iPhone-5s";	
				altCommand = true;
			}
			
			if (project.targetFlags.exists ("tall47")) {
				tall = "com.apple.CoreSimulator.SimDeviceType.iPhone-6";
				altCommand = true;
			}
			
			if (project.targetFlags.exists ("tall55")) {
				tall = "com.apple.CoreSimulator.SimDeviceType.iPhone-6-Plus";
				altCommand = true;
			}
			
			var templatePaths = [ PathHelper.combine (PathHelper.getHaxelib (new Haxelib ("lime")), "templates") ].concat (project.templatePaths);
			var launcher = PathHelper.findTemplate (templatePaths, "bin/ios-sim");
			Sys.command ("chmod", [ "+x", launcher ]);
			
			if(altCommand)
			{
				ProcessHelper.runCommand ("", launcher, [ "launch", FileSystem.fullPath (applicationPath), "--sdk", project.environment.get ("IPHONE_VER"), "--devicetypeid", tall, "--timeout", "30", "--stdout", project.environment.get ("IPHONE_STDOUT")]  );
			}
			
			else
			{
				ProcessHelper.runCommand ("", launcher, [ "launch", FileSystem.fullPath (applicationPath), "--sdk", project.environment.get ("IPHONE_VER"), "--family", family, retina, tall, "--timeout", "30", "--stdout", project.environment.get ("IPHONE_STDOUT")]  );
			}
		} else {
			
			var applicationPath = "";
			
			if (Path.extension (workingDirectory) == "app" || Path.extension (workingDirectory) == "ipa") {
				
				applicationPath = workingDirectory;
				
			} else {
				
				applicationPath = workingDirectory + "/build/" + configuration + "-iphoneos/" + project.app.file + ".app";
				
			}
			
			var templatePaths = [ PathHelper.combine (PathHelper.getHaxelib (new Haxelib ("lime")), "templates") ].concat (project.templatePaths);
			var launcher = PathHelper.findTemplate (templatePaths, "bin/ios-deploy");
			Sys.command ("chmod", [ "+x", launcher ]);
			
			var xcodeVersion = getXcodeVersion ();
			
			ProcessHelper.runCommand ("", launcher, [ "install", "--noninteractive", "--debug", "--timeout", "5", "--bundle", FileSystem.fullPath (applicationPath) ]);
			
		}
		
	}
	
	
	public static function sign (project:HXProject, workingDirectory:String, entitlementsPath:String):Void {
		
		initialize (project);
		
		var configuration = "Release";
		
		if (project.debug) {
			
			configuration = "Debug";
			
		}
		
		var identity = "iPhone Developer";
		
		if (project.certificate != null && project.certificate.identity != null) {
			
			identity = project.certificate.identity;
			
		}
		
        var commands = [ "--no-strict", "-f", "-s", identity ];
		
		if (entitlementsPath != null) {
			
			commands.push ("--entitlements");
			commands.push (entitlementsPath);
			
		}
		
		var applicationPath = "build/" + configuration + "-iphoneos/" + project.app.file + ".app";
		commands.push (applicationPath);
		
		ProcessHelper.runCommand (workingDirectory, "codesign", commands, true, true);
		
	}
	

}
