using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class ReviewPanel : Panel {
        public ReviewPanel (PublishWindow win) {
            base (win);
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            if (pub.comments.size == 0) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                wp.title = _("Review");
                wp.subtitle = _("Send a PDF proof for comments and bring the comments back as notes on the pages");
                wp.add_action ("singularity-share-send-files", _("Send for Review"), _("Export a proof PDF and open it in Reader"), () => win.run ("send-for-review"));
                wp.add_action ("document-open", _("Import Comments"), _("Read the comments of a reviewed PDF"), () => win.run ("import-comments"));
                content.append (wp);
                return;
            }
            int open = 0;
            foreach (var c in pub.comments) if (!c.resolved) open++;
            var g = group (_("Comments"), ngettext ("%d open comment", "%d open comments", open).printf (open));
            header_button (g, _("Import…"), () => win.run ("import-comments"));
            foreach (var cm in pub.comments) {
                var c = cm;
                string title = c.text != "" ? c.text : c.kind;
                string sub = "%s, %s".printf (c.author != "" ? c.author : _("Reviewer"), _("Page %s").printf (pub.page_label (c.page)));
                if (c.quoted != "") sub += ", “%s”".printf (c.quoted);
                foreach (var r in c.replies) sub += "\n%s: %s".printf (r.author, r.text);
                var row = new ActionRow (title, sub);
                if (c.resolved) row.add_css_class ("dim-label");
                var done = new ToggleButton ();
                done.icon_name = "object-select-symbolic";
                done.active = c.resolved;
                done.valign = Align.CENTER;
                done.add_css_class ("flat");
                done.add_css_class ("sx-layer-toggle");
                if (!c.resolved) done.add_css_class ("sx-off");
                done.tooltip_text = c.resolved ? _("Reopen") : _("Mark as Resolved");
                done.update_property (AccessibleProperty.LABEL, done.tooltip_text, -1);
                done.toggled.connect (() => {
                    bool v = done.active;
                    win.edit (_("Resolve Comment"), () => c.resolved = v);
                    win.canvas.queue_draw ();
                    rebuild ();
                });
                var go = icon ("find-location-symbolic", _("Show"));
                go.clicked.connect (() => win.go_to_page (c.page));
                row.add_suffix (go);
                var del = icon ("user-trash-symbolic", _("Delete"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Comment"), () => pub.comments.remove (c));
                    rebuild ();
                    win.canvas.queue_draw ();
                });
                row.add_suffix (del);
                row.add_suffix (done);
                g.add_row (row);
            }
            var sg = group (_("Proofs"));
            var send = new ActionRow (_("Send for Review"), _("Export a proof PDF and open it in Reader"));
            var sb = new Button.with_label (_("Send"));
            sb.valign = Align.CENTER;
            sb.clicked.connect (() => win.run ("send-for-review"));
            send.add_suffix (sb);
            sg.add_row (send);
        }

        public static void install (PublishWindow w) {
            w.doc_action ("send-for-review", () => {
                string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-publish", "proofs");
                DirUtils.create_with_parents (dir, 0700);
                string path = Path.build_filename (dir, "%s %s.pdf".printf (w.base_name (_("Publication")), _("proof")));
                try {
                    new Exporter (w.doc.pub, new ExportOptions ()).export_pdf (path);
                    var t = new Toast (_("Proof saved; comment it in Reader, then import the comments"));
                    t.button_label = _("Open");
                    t.button_clicked.connect (() => open_in_reader (w, path));
                    w.add_toast (t);
                    open_in_reader (w, path);
                } catch (Error e) {
                    w.show_error (_("Could Not Create the Proof"), e.message);
                }
            });
            w.doc_action ("import-comments", () => {
                var dialog = new FileDialog ();
                dialog.title = _("Import Comments from a PDF");
                var filters = new GLib.ListStore (typeof (FileFilter));
                filters.append (PublishWindow.filter (_("PDF Documents"), { "pdf" }));
                dialog.filters = filters;
                dialog.open.begin (w, null, (o, res) => {
                    try {
                        var f = dialog.open.end (res);
                        if (f == null || f.get_path () == null) return;
                        int n = 0;
                        Error? err = null;
                        w.edit (_("Import Comments"), () => {
                            try {
                                n = Review.import_pdf (w.doc.pub, f.get_path ());
                            } catch (Error e) {
                                err = e;
                            }
                        });
                        if (err != null) throw err;
                        w.toast (ngettext ("Imported %d comment", "Imported %d comments", n).printf (n));
                        w.toggle_panel ("review", true);
                        w.canvas.queue_draw ();
                    } catch (Error e) {
                        if (!(e is DialogError.DISMISSED)) w.show_error (_("Could Not Import the Comments"), e.message);
                    }
                });
            });
        }

        private static void open_in_reader (PublishWindow w, string path) {
            var file = File.new_for_path (path);
            AppInfo? info = null;
            foreach (var a in AppInfo.get_all ()) if (a.get_id () == "dev.sinty.reader.desktop") info = a;
            try {
                var list = new GLib.List<File> ();
                list.append (file);
                if (info != null) info.launch (list, w.get_display ().get_app_launch_context ());
                else AppInfo.launch_default_for_uri (file.get_uri (), w.get_display ().get_app_launch_context ());
            } catch (Error e) {
                w.toast (_("Saved the proof as \"%s\"").printf (path));
            }
        }
    }
}
