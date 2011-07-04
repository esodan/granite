//  
//  Copyright (C) 2011 Robert Dyer, Rico Tzschichholz
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

namespace Granite.Services {

	/**
	 * This interface is used by objects that need to be serialized in a Settings.
	 * The object must have a string representation and provide these methods to
	 * translate between the string and object representations.
	 */
	public interface SettingsSerializable : GLib.Object {
		/**
		 * Serializes the object into a string representation.
		 *
		 * @return the string representation of the object
		 */
		public abstract string settings_serialize ();
		
		/**
		 * Un-serializes the object from a string representation.
		 *
		 * @param s the string representation of the object
		 */
		public abstract void settings_deserialize (string s);
	}
	
	/**
	 * Class for interacting with an internal {@link GLib.Settings} using native Vala properties.
	 * Clients of this class should not connect to the {@link GLib.Object.notify()} signal.
	 * Instead, they should connect to the {@link Granite.Services.Settings.changed()} signal.
	 *
	 * For example, if a developer wanted to interact with desktop.Wallpaper's (http:/www.launchpad.net/pantheon-wallpaper) schema,
	 * this is what his/her subclass might look like:
	 *
	 * {{{
	 *    public class WallpaperSettings : Granite.Services.Settings {
	 *    
	 *        public PictureMode picture_mode { get; set; }
	 *    
	 *        public string picture_path { get; set; }
	 *    
	 *        public string background_color { get; set; }
	 *    
	 *        public WallpaperSettings () {
	 *            base ("desktop.Wallpaper");
	 *        }
	 *    
	 *        protected override void verify (string key) {
	 *    
	 *            switch (key) {
	 *    
	 *                case "background-color":
	 *                    Gdk.Color bg;
	 *                    if (!Gdk.Color.parse (background_color, out bg))
	 *                        background_color = "#000000";
	 *                    break;
	 *            }
	 *        }
	 *    
	 *    }
	 * }}}
	 *
	 * Keep in mind that the developer must define his/her enums to match the schema's.
	 * 
	 * The following is a simplified explanation of how this library works:
	 *  1. Any subclass looks at all properties it contains, and loads their initial values from the keys they represent.
	 *     Because Vala properties are stored as GLib properties, the string representation of a property replaces underscores with
	 *     hyphens (i.e. property_name becomes "property-name"). This is how this library knows which keys to load from. If the key
	 *     does not exist, it will result in a fatal error.
	 *  1. When a property of the subclass changes, the library will first verify the data before emitting a changed signal. If necessary,
	 *     the library will change the value of the property while verifying.
	 *     This is why developers should only act upon emissions of the changed () signal and never the native {@link GLib.Object.notify()} signal.
	 *  1. When the corresponding key of one of the properties of the subclass changes, it will also verify the data and change it, if necessary,
	 *     before loading it into as the corresponding property's value.
	 */
	public abstract class Settings : GLib.Object {
	
		/**
		 * This signal is to be used in place of the standard {@link GLib.Object.notify()} signal.
		 *
		 * This signal ''only'' emits after a property's value was verified.
		 *
		 * Note that in the case where a property was set to an invalid value,
		 * (and thus, sanitized to a valid value), the {@link GLib.Object.notify()} signal will emit 
		 * twice: once with the invalid value and once with the sanitized value.
		 */
		[Signal (no_recurse = true, run = "first", action = true, no_hooks = true, detailed = true)]
		public signal void changed ();
	
		private GLib.Settings schema;
		
		/**
		 * Creates a new {@link Granite.Services.Settings} object for the supplied schema.
		 *
		 * @param schema the name of the schema to interact with
		 */
		public Settings (string schema) {
			this.schema = new GLib.Settings (schema);
			init ();
		}
		
		/**
		 * Creates a new {@link Granite.Services.Settings} object for the supplied schema and {@link GLib.SettingsBackend}.
		 *
		 * @param schema the name of the schema to interact with
		 * @param backend the desired backend to use
		 */
		public Settings.with_backend (string schema, SettingsBackend backend) {
			this.schema = new GLib.Settings.with_backend (schema, backend);
			init ();
		}
		
		/**
		 * Creates a new {@link Granite.Services.Settings} object for the supplied schema, {@link GLib.SettingsBackend}, and path.
		 * 
		 * This is a mix of {@link Granite.Services.Settings.with_backend()} and {@link Granite.Services.Settings.with_path()}.
		 *
		 * @param schema the name of the schema to interact with
		 * @param backend the desired backend to use
		 * @param path the path to use
		 */
		public Settings.with_backend_and_path (string schema, SettingsBackend backend, string path) {
			this.schema = new GLib.Settings.with_backend_and_path (schema, backend, path);
			init ();
		}
		
		/**
		 * Creates a new {@link Granite.Services.Settings} object for the supplied schema, and path.
		 * 
		 * You only need to do this if you want to directly create a settings object with a schema that
		 * doesn't have a specified path of its own. That's quite rare.
		 *
		 * It is a programmer error to call this function for a schema that has an explicitly specified path.
		 *
		 * @param schema the name of the schema to interact with
		 * @param path the path to use
		 */
		public Settings.with_path (string schema, string path) {
			this.schema = new GLib.Settings.with_path (schema, path);
			init ();
		}
		
		private void init () {
		
			debug ("Loading settings from schema '%s'", schema.schema);
			
			var obj_class = (ObjectClass) get_type ().class_ref ();
			var properties = obj_class.list_properties ();
			foreach (var prop in properties)
				load_key (prop.name);
			
			start_monitor ();
		}
		
		~Settings () {
			stop_monitor ();
		}
		
		/**
		 * Create a binding between the //key// and the property //property// of //object//.
		 * 
		 * The binding uses the default GIO mapping functions to map between the settings and property values. These functions handle booleans,
		 * numeric types and string types in a straightforward way. Use {@link GLib.Settings.bind_with_mapping()} if you need a custom
		 * mapping, or map between types that are not supported by the default mapping functions.
		 *
		 * Unless the flags include {@link GLib.SettingsBindFlags.NO_SENSITIVITY}, this method also establishes a binding between the
		 * writability of //key// and the "sensitive" property of object (if object has a boolean property by that name).
		 * See {@link GLib.Settings.bind_writable()} for more details about writable bindings.
		 *
		 * Note that the lifecycle of the binding is tied to the object, and that you can have only one binding per object property. If you
		 * bind the same property twice on the same object, the second binding overrides the first one.
		 *
		 * @param key the key to bind
		 * @param object the object containing //property//
		 * @param property the name of the property to bind (see notes above about the GLib naming style for properties)
		 * @param flags the flags for the binding
		 */
		public void bind (string key, void* object, string property, SettingsBindFlags flags = GLib.SettingsBindFlags.DEFAULT) {
			schema.bind (key, object, property, flags);			
		}
		
		private void stop_monitor () {
			
			schema.changed.disconnect (load_key);
		}
		
		private void start_monitor () {
			
			schema.changed.connect (load_key);
		}
		
		void handle_notify (Object sender, ParamSpec property) {
		
			notify.disconnect (handle_notify);
			call_verify (property.name);
			notify.connect (handle_notify);
			
			save_key (property.name);
		}
		
		void handle_verify_notify (Object sender, ParamSpec property) {
		
			warning ("Key '%s' failed verification in schema '%s', changing value", property.name, schema.schema);
			
			save_key (property.name);
		}
		
		private void call_verify (string key) {
		
			notify.connect (handle_verify_notify);
			verify (key);
			changed[key] ();
			notify.disconnect (handle_verify_notify);
		}
		
		/**
		 * Verify the given key, changing the property if necessary. Refer to the example given for the class.
		 *
		 * @param key the key in question
		 */
		protected virtual void verify (string key)	{
			// do nothing, this isnt abstract because we dont
			// want to force subclasses to implement this
		}
		
		void load_key (string key) {
		
			notify.disconnect (handle_notify);
		
			var obj_class = (ObjectClass) get_type ().class_ref ();
			var prop = obj_class.find_property (key);
			
			var type = prop.value_type;
			var val = Value (type);
			
			if (type == typeof (int))
				val.set_int (schema.get_int (key));
			else if (type == typeof (double))
				val.set_double (schema.get_double (key));
			else if (type == typeof (string))
				val.set_string (schema.get_string (key));
			else if (type == typeof (bool))
				val.set_boolean (schema.get_boolean (key));
			else if (type.is_enum ())
				val.set_enum (schema.get_enum (key));
			else if (type.is_a (typeof (SettingsSerializable))) {
				get_property (prop.name, ref val);
				(val.get_object () as SettingsSerializable).settings_deserialize (schema.get_string (key));
				notify.connect (handle_notify);
				return;
			} else {
				debug ("Unsupported settings type '%s' for key '%' in schema '%s'", type.name (), key, schema.schema);
				notify.connect (handle_notify);
				return;
			}
			
			set_property (prop.name, val);
			call_verify (prop.name);
			
			notify.connect (handle_notify);
		}
		
		void save_key (string key) {
		
			stop_monitor ();
			
			var obj_class = (ObjectClass) get_type ().class_ref ();
			var prop = obj_class.find_property (key);
				
			var type = prop.value_type;
			var val = Value (type);
			get_property (prop.name, ref val);
			
			if (type == typeof (int))
				schema.set_int (prop.name, val.get_int ());
			else if (type == typeof (double))
				schema.set_double (prop.name, val.get_double ());
			else if (type == typeof (string))
				schema.set_string (prop.name, val.get_string ());
			else if (type == typeof (bool))
				schema.set_boolean (prop.name, val.get_boolean ());
			else if (type.is_enum ())
				schema.set_enum (prop.name, val.get_enum ());
			else if (type.is_a (typeof (SettingsSerializable)))
				schema.set_string (prop.name, (val.get_object () as SettingsSerializable).settings_serialize ());
			else
				debug ("Unsupported settings type '%s' for key '%' in schema '%s'", type.name (), prop.name, schema);
			
			start_monitor ();
		}
		
	}
	
}

