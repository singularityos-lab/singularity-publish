using GLib;
using Gtk;
using Singularity.Accounts;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public delegate void CloudFileFunc (GLib.File file);

    public class CloudActions : Object {
        private static string[] mime_types () {
            return {
                NativeFormat.MIME,
                "application/vnd.scribus",
                "application/x-scribus",
                "application/vnd.adobe.indesign-idml-package",
                "application/x-mspublisher",
                "application/vnd.ms-publisher"
            };
        }

        public static async void open (Gtk.Window window, owned CloudFileFunc open_file) {
            var file = yield CloudFileDialog.open (window, mime_types ());
            if (file != null) open_file (file.local);
        }

        public static async void save (Singularity.Widgets.Window window, string name,
                                       owned CloudFileFunc write, owned CloudFileFunc adopt) {
            string dir;
            try {
                dir = DirUtils.make_tmp ("singularity-publish-XXXXXX");
            } catch (Error e) {
                window.add_toast (new Toast (e.message));
                return;
            }
            var source = GLib.File.new_for_path (Path.build_filename (dir, name));
            write (source);
            CloudFile? cloud = null;
            if (source.query_exists ()) cloud = yield CloudFileDialog.save (window, source, name);
            FileUtils.remove (source.get_path ());
            DirUtils.remove (dir);
            if (cloud == null) return;
            adopt (cloud.local);
            window.add_toast (new Toast (_("Saved to %s").printf (account_name (cloud.local))));
        }

        public static void save_document (PublishWindow window) {
            var doc = window.doc;
            if (doc == null) return;
            string name = doc.path != null ? Path.get_basename (doc.path) : _("Publication") + "." + NativeFormat.EXT;
            var k = FileKind.from_path (name);
            if (!k.can_save ()) {
                int dot = name.last_index_of (".");
                name = (dot > 0 ? name.substring (0, dot) : name) + "." + NativeFormat.EXT;
            }
            save.begin (window, name, (f) => {
                try {
                    FileUtils.set_data (f.get_path (), Document.serialize (doc.pub, FileKind.from_path (f.get_path ())));
                } catch (Error e) {
                    window.show_error (_("Could Not Save"), e.message);
                }
            }, (f) => {
                doc.path = f.get_path ();
                doc.pub.base_dir = Path.get_dirname (f.get_path ());
                doc.modified = false;
                doc.changed ();
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (f.get_uri ());
            });
        }

        public static void sync_back (Singularity.Widgets.Window window, GLib.File file) {
            CloudFile.sync_back.begin (file, null, (obj, res) => {
                try {
                    if (CloudFile.sync_back.end (res))
                        window.add_toast (new Toast (_("Saved to %s").printf (account_name (file))));
                } catch (Error e) {
                    window.add_toast (new Toast (_("Not saved to %s: %s").printf (account_name (file), e.message)));
                }
            });
        }

        private static string account_name (GLib.File file) {
            var cloud = CloudFile.for_local (file);
            var account = cloud != null ? Manager.get_default ().get_account (cloud.account_id) : null;
            return account != null ? account.display_name : _("Online Account");
        }
    }
}
