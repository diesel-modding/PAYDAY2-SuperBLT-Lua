import "base/native" for Logger, IO, XML
import "base/native/Environment_001" for Environment
import "base/private/json" for Json

/**
 * XML Tweak Applier
 *
 * This loads and applies XML tweak files
 */
class XMLTweakApplier {
	construct new() {
		/**
		 * A map of lists of tweak filenames
		 * Here's an example value of it (in Lua syntax):
		 * _xml_tweaks = {
		 *   ["2301c70c9bd10234.e8cc76b954399722"] = { -- light intensity db
		 *     "mods/mytest/mytweak-1.xml",
		 *     "mods/mytest/mytweak-2.xml",
		 *     "mods/myothermod/tweak.xml",
		 *   },
		 * }
		 */
		_xml_tweaks = {}
		/**
		 * Bump this if breaking changes to the tweak format or behavior occur
		 * 1/(unspecified): Initial release
		 * 2: 'replace' and 'append' modes now insert nodes in the expected order (see !19)
		 */
		_current_version = 2

		/**
		* A table of mods and metadata about them
		*/
		_mods = {}

		/**
		 * A list of the state of all the control keys
		 */
		_control_keys = {}
	}

	// Mark that an XML file <path> tweaks the bundled file <name>.<ext>
	add_tweak(name, ext, path) {
		// Check the tweak list exists
		var full = "%(name).%(ext)"
		if(_xml_tweaks[full] == null) _xml_tweaks[full] = []
		var tweaklist = _xml_tweaks[full]

		// Ensure we don't add the same tweak twice
		for(tweak in tweaklist) {
			if(tweak == path) return
		}

		// Add the tweak
		tweaklist.add(path)
	}

	tweaked_files {
		return _xml_tweaks.keys
	}

	mods_data {
		return _mods
	}

	// Returns whether or not the tweaker needs to tweak the bundled file <name>.<ext>
	tweaks(name, ext) {
		var full = "%(name).%(ext)"
		return _xml_tweaks[full] != null
	}

	// Tweak an XML file
	tweak_xml(name, ext, xml) {
		// Find the tweak list
		var full = "%(name).%(ext)"
		var tweaks = _xml_tweaks[full]

		// Apply each of the required tweaks
		for(path in tweaks) {
			apply_tweak(name, ext, xml, path)
		}
	}

	/**
	 * Enable or disable all the tweaks keyed to a given control key.
	 */
	set_control_key(mod, key, state) {
		_control_keys["%(mod)::%(key)"] = state
	}

	/**
	 * Apply a tweak file to a bundled file
	 *
	 * @param name The (hashed) name of the bundle file
	 * @param ext The (hashed) extension of the bundle file
	 * @param xml The XML object representation of the bundled file
	 * @param tweak_path The path of the tweak file to read and apply
	 */
	apply_tweak(name, ext, xml, tweak_path) {
		// Find all the relevant tweaks
		var tweaks = [] // List of XML elements representing `<tweak>` tags
		find_tweaks(tweak_path, name, ext, tweaks)

		// As with pairs() in Lua, Wren makes no guarantees about the iteration order of maps
		// (see https://wren.io/maps.html#iterating-over-the-contents). Fortunately, tweaks is a
		// list (since new elements are appended with .add() in handle_tweak_element() below),
		// so iteration order should be consistent enough to be tracked this way (or if need be,
		// indexing it like an array within a range loop)
		var tweak_index = 0
		for(tweak in tweaks) {
			tweak_index = tweak_index + 1
			// Search for the <search> and <target> elements
			var search_node = null
			var target_node = null

			for (elem in tweak.element_children) {
				var name = elem.name
				if(name == "search") {
					// TODO raise error if duplicate search elements exist
					search_node = elem
				} else if(name == "target") {
					// TODO raise error if duplicate target elements exist
					target_node = elem
				} else {
					Fiber.abort("Unknown element type in %(tweak_path): %(name)")
				}
			}

			// Verify the presence of the search and target nodes
			if(search_node == null) Fiber.abort("Missing <search> node in %(tweak_path)")
			if(target_node == null) Fiber.abort("Missing <target> node in %(tweak_path)")

			var tweakversion = tweak["version"]
			if(tweakversion is String) {
				tweakversion = Num.fromString(tweakversion)
				if(tweakversion == null || tweakversion < 1) {
					tweakversion = _current_version
					Logger.log("Warning: Unrecognized tweak version specified; assuming %(tweakversion) instead.")
				} else {
					// Integers only, please. Using .floor instead of .round to ensure that all
					// fractional values that exceed _current_version are still considered the
					// same as their integer portion
					tweakversion = tweakversion.floor
					if(tweakversion > _current_version) {
						Logger.log("Warning: A tweak version (%(tweakversion)) greater than the current version (%(_current_version)) has been specified. This may cause problems in future.")
					}
				}
			} else {
				// Missing version attribute
				tweakversion = 1
			}

			var info = {
				"count": 0,
				"tweakversion": tweakversion,
				"level": 0, // This tracks the recursion depth of dive_tweak_elem()
				"deepestlevel": 0 // This tracks the deepest ever level of recursion, which is
								  // usually good enough for pointing out problematic search
								  // nodes
			}
			dive_tweak_elem(xml.ensure_element_next, search_node, search_node.first_child.ensure_element_next, target_node, info)

			if(info["count"] == 0) {
				Logger.log("Warning: Failed to apply tweak %(tweak_index) of %(tweaks.count) in %(tweak_path) for %(name).%(ext)")
				// Pulling info["deepestlevel"] into its own variable because it makes string
				// literals hard to read when embedded within them
				var deepestlevel = info["deepestlevel"]
				var search_elements = search_node.element_children
				var failed_node = search_elements[deepestlevel]
				var last_found_node = (deepestlevel >= 1) ? search_elements[deepestlevel - 1] : null
				Logger.log("  Failure details:")
				// Using .name instead of .string because the latter is unstable and has a high
				// chance of crashing out
				Logger.log("    Failed to find node: #%(deepestlevel + 1) <%(failed_node.name) />")
				if(last_found_node != null) {
					Logger.log("    Last found node: #%(deepestlevel) <%(last_found_node.name) />")
				} else {
					Logger.log("    Last found node: (none)")
				}
				Logger.log("  You may inadvertently have specified an intermediate node that doesn't have any child nodes, such as <else />")
				Logger.log("  Alternatively, you may have missed out an intermediate node that subsequent search nodes are child nodes of")
				Logger.log("  Please verify your list of search nodes against an up-to-date, pristine copy of the game's XML file")
			}
		}

		// Close all the tweaks
		for(tweak in tweaks) {
			tweak.delete()
		}
	}

	dive_tweak_elem(xml, root_search_node, search_node, target_node, info) {
		var elem = xml
		while (elem != null) {
			if(elem.name == search_node.name) {
				var match = true
				for(name in search_node.attribute_names) {
					if(search_node[name] != elem[name]) {
						match = false
						break
					}
				}
				// TODO something with elem.attribute_names == search_node.attribute_names

				if(match) {
					info["level"] = info["level"] + 1
					var next_search_node = search_node.next_element
					if(next_search_node == null) {
						var mult = target_node["multiple"] == "true"
						info["count"] = info["count"] + 1

						apply_tweak_elem(elem, target_node, mult, target_node["mode"], info["tweakversion"])

						if(!mult) return false
					} else {
						var continue_search = dive_tweak_elem(elem.first_child, root_search_node, next_search_node, target_node, info)
						if(!continue_search) {
							return false
						}

						if(info["level"] > info["deepestlevel"]) {
							info["deepestlevel"] = info["level"]
						}
						info["level"] = info["level"] - 1
					}
				}
			}
			elem = elem.next_element
		}

		return true
	}

	// We've found a element that maches the search tag, now tweak it
	apply_tweak_elem(xml, target_node, multiple, mode, version) {
		if (mode == "attributes") {
			for (elem in target_node.element_children) {
				if(elem.name != "attr") Fiber.abort("In unknown attributes target: bad elem <%(elem.name)>, should be <attr>")
				xml[elem["name"]] = elem["value"]
			}
			return
		}

		var insert_after = mode == "replace" || mode == "append"

		var previous_child = xml
		if(insert_after) xml = xml.parent
		var child_to_append_to = previous_child

		for (elem in target_node.element_children) {
			if(multiple) {
				elem = elem.clone()
			} else {
				elem.detach()
			}
			if(insert_after) {
				xml.attach(elem, child_to_append_to)
				if(version > 1) {
					child_to_append_to = elem
				}
			} else {
				xml.attach(elem)
			}
		}

		if(mode == "replace") previous_child.detach().delete()
	}

	find_tweaks(path, name, ext, tweaks) {
		var data = IO.read(path)
		var xml = XML.new(data)
		var root = xml.first_child // <?xml?> -> <tweak/tweaks>
		var tweaked = false
		if(root.name == "tweaks") {
			for (elem in root.element_children) {
				if(handle_tweak_element(path, name, ext, elem, tweaks)) tweaked = true
			}
		} else if(root.name == "tweak") {
			if(handle_tweak_element(path, name, ext, root, tweaks)) tweaked = true
		} else {
			Logger.log("[WARN] Unknown tweak root type in %(path): %(root.name)")
		}
		if(!tweaked) xml.delete()
	}

	handle_tweak_element(path, name, ext, elem, tweaks) {
		if(name != XMLTweakApplier.handle_idstring(elem["name"])) return false
		if(ext != XMLTweakApplier.handle_idstring(elem["extension"])) return false

		// The control-key attribute lets the mod enable and disable this tweak at runtime
		var control_key = elem["control-key"]
		if (control_key != null) {
			// Hacky stuff to get the mod path prefix for the control key
			var path_parts = path.split("/")
			var full_key = "mods/%(path_parts[1])::%(control_key)"

			Logger.log("keys: %(_control_keys) vs %(full_key)")
			if (control_key && _control_keys[full_key] != true) return false
		}

		tweaks.add(elem)
		return true
	}

	static handle_idstring(input) {
		if(input[0] == "#") {
			return input[1..16]
		} else {
			return IO.idstring_hash(input)
		}
	}
}

class ModErrorHandlerImpl {
	construct new() {
		// This will be overridden by asset_loader_tweaks if the basemod supports it
		_func = Fn.new { | file, err |
			Fiber.abort("Wren run error for %(file): %(err)")
		}
	}

	func { _func }
	func=(v) { _func = v }
}

var ExecTodo = []
var Tweaker = XMLTweakApplier.new()
var ModErrorHandler = ModErrorHandlerImpl.new()

class XMLLoader {
	static init() {
		// Check for disabled mods
		var blt_data_path = "mods/saves/blt_data.txt"

		// Create a fiber to check if we are running in VR to prevent crashes with outdated dll versions
		(Fiber.new {
			var blt_data_path_vr = "mods/saves/blt_data_vr.txt"
			if (Environment.is_vr && IO.info(blt_data_path_vr) == "file") {
				blt_data_path = blt_data_path_vr
			}
		}).try()

		// Load disabled mods from the BLT savefile
		var disabled_mods = {}
		if (IO.info(blt_data_path) == "file") {
			(Fiber.new {
				var json_data = Json.parse(IO.read(blt_data_path))
				var mod_data = json_data["mods"] // Fallback to savedata before profiles
				var profiles = json_data["profiles"]
				if (profiles) {
					var profile_index = json_data["profile_index"] == null ? 0 : json_data["profile_index"]
					profile_index = profile_index.clamp(1, profiles.count)
					var profile = profiles[profile_index - 1]
					if (profile && profile["mods"]) {
						mod_data = profile["mods"]
					}
				}

				if (mod_data) {
					for (entry in mod_data) {
						if (entry.value["enabled"] == false) {
							disabled_mods[entry.key] = true
						}
					}
				}
			}).try()
		}

		// Sort by priority value
		var mods_by_priority = []
		var mod_names = IO.listDirectory("mods", true)

		for (mod in mod_names) {
			var mod_data_path = "mods/%(mod)/mod.txt"
			// Skip over disabled mods
			if (disabled_mods[mod]) {
				continue
			}

			if (IO.info(mod_data_path) != "file") {
				mods_by_priority.add(ModData.new(mod, 0))
				continue
			}

			var priority = 0
			(Fiber.new {
				var json_data = Json.parse(IO.read(mod_data_path))
				if (json_data["priority"] is Num) {
					priority = json_data["priority"]
				} else if (json_data["priority"] is String) {
					priority = Num.fromString(json_data["priority"])
				}
			}).try()

			mods_by_priority.add(ModData.new(mod, priority))
		}
		mods_by_priority.sort {| a, b | a.priority > b.priority }

		if (IO.info("assets/mod_overrides") == "dir") {
			for (mod in IO.listDirectory("assets/mod_overrides", true)) {
				load_supermod_file("assets/mod_overrides/%(mod)", null, true)
			}
		}

		for (mod_data in mods_by_priority) {
			Tweaker.mods_data[mod_data.name] = mod_data
			load_supermod_file("mods/%(mod_data.name)", mod_data, false)
		}
	}

	static exec_wren_scripts() {
		for (file in ExecTodo) {
			Logger.log("Loading module %(file)")
			var err = (Fiber.new {
				IO.dynamic_import("__raw_force_load/" + file)
			}).try()
			if (err != null) {
				ModErrorHandler.func.call(file, err)
			}
		}
	}

	static load_supermod_file(mod_path, mod_data, tweak_only) {
		var path = "%(mod_path)/supermod.xml"

		if (IO.info(path) != "file") {
			return
		}

		// Disable Wren and Tweaks if flags desktop_disabled or vr_disabled are true
		var mod_txt_path = "%(mod_path)/mod.txt"
		var do_tweaks = true

		if (IO.info(mod_txt_path) == "file") {
			(Fiber.new {
				var json_data = Json.parse(IO.read(mod_txt_path))
				if (json_data["desktop_disabled"] && !Environment.is_vr || json_data["vr_disabled"] && Environment.is_vr) {
					do_tweaks = false
				}
			}).try()
		}

		if (!do_tweaks) {
			return
		}

		var xml_data = IO.read(path)
		var xml = XML.new(xml_data)

		for (elem in xml.first_child.element_children) { // <?xml?> -> <mod> -> first elem
			var name = elem.name

			// Only allow tweaks in mod_overrides
			if (tweak_only && name != "tweak") {
				Fiber.abort("Non-tweak element in mod_overrides mod in %(mod_path):<wren>: %(name)")
			}

			if(name == ":include") {
				// TODO include logic
			} else if(name == "wren") {
				handle_wren_tag(mod_path, elem, mod_data)
			} else if(name == "tweak") {
				handle_tweak_file(mod_path, elem["definition"])
			} else if(name == "native_module") {
				handle_native_module(mod_path, elem)
			} else {
				// Since this XML file is also potentially used by Lua, don't do anything
				// Fiber.abort("Unknown element type in %(path): %(name)")
			}
		}
		xml.delete()
	}

	static handle_wren_tag(mod, tag, mod_data) {
		// Awful hack:
		// Old versions of SuperBLT didn't load Wren files properly, and required the path to be baked in. Because
		// of my (ZNix's) bad idea of making everything throw errors rather than logging warnings (which was and
		// still is great for making people comply with the specifications) it has become impossible to use the init
		// tag to load a file on a mod that needs backwards compatibility with older versions of SuperBLT.
		// As a result, I'm pretty much forced at this point to let you specify the file to load via an attribute
		// on the wren tag, to allow for this kind of backwards-compatiblity.
		if (tag["init-file"] != null) {
			var mod_name = mod.replace("mods/", "")
			var file_name = tag["init-file"]
			ExecTodo.add("%(mod_name)/%(file_name)")
		}

		// Let the mod change the directory that all Wren scripts are relative to - by default this is 'wren'
		if (tag["scripts-root"] != null) {
			mod_data.scripts_root = tag["scripts-root"]
		}

		for (elem in tag.element_children) {
			var name = elem.name
			if(name == "base-path") {
				// TODO set base path
			} else if(name == "init") {
				var mod_name = mod.replace("mods/", "")
				var file_name = elem["file"]
				ExecTodo.add("%(mod_name)/%(file_name)")
			} else {
				Logger.log("[WARN] Unknown element type in %(mod):<wren>: %(name)")
			}
		}
	}

	static handle_tweak_file(mod, filename) {
		var path = "%(mod)/%(filename)"
		var data = IO.read(path)
		var xml = XML.new(data)
		var root = xml.first_child // <?xml?> -> <tweak/tweaks>

		if(root.name == "tweaks") {
			for (elem in root.element_children) {
				handle_tweak_element(mod, path, elem)
			}
		} else if(root.name == "tweak") {
			handle_tweak_element(mod, path, root)
		} else {
			Logger.log("[WARN] Unknown tweak root type in %(path): %(root.name)")
		}

		xml.delete()
	}

	static handle_tweak_element(mod, path, root) {
		var name = XMLTweakApplier.handle_idstring(root["name"])
		var extension = XMLTweakApplier.handle_idstring(root["extension"])
		Tweaker.add_tweak(name, extension, path)
	}

	static handle_native_module(mod, elem) {
		// Lua handles everything except "preload" DLLs
		if(elem["loading_vector"] != "preload") return

		var path = "%(mod)/%(elem["filename"])"

		// TODO check platform/architecture

		Logger.log("Loading native plugin for mod \"%(mod)\"")

		IO.load_plugin(path)
	}
}

class ModData {
	construct new(name, priority) {
		_name = name
		_priority = priority
		_scripts_root = "wren"
	}

	name { _name }
	priority { _priority }
	scripts_root { _scripts_root }
	scripts_root=(v) { _scripts_root = v }
}

XMLLoader.init()

// If we're running a version of the DLL that supports DB hooking, use that rather than the old
// hooking system. If we're not, this will fail to handle the error accordingly.
// Also note this will use the list of installed tweaks, so this must be called after XMLLoader.init or
// some tweaks won't be applied.
var db_err = (Fiber.new {
	// Since the old (and very against-wren-docs) dynamic_import method crashes the game if there's an
	// error loading the script, call a method that we know doesn't exist previously to force the fibre
	// to stop here.
	IO.has_native_module("")

	IO.dynamic_import("base/private/asset_loader_tweaks")

	// Only run other mod's scripts if the basemod supports doing so
	XMLLoader.exec_wren_scripts()
}).try()

if (db_err != null) {
	Logger.log("Failed to load DB-hook based asset tweaker. Please update your DLL, as this fixes occasional crashes.")
	Logger.log("Error for the above: %(db_err)")
}
