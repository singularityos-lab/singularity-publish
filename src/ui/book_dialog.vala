using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class BookDialog {
        private static Book? current = null;

        public static void install (PublishWindow w) {
            w.doc_action ("book", () => {
                if (current != null) manage (w, current);
                else start (w);
            });
        }

        private static void start (PublishWindow w) {
            var dlg = Dialogs.make (w, _("Book"), 480, 360);
            var box = Dialogs.body (dlg);
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.app_icon_name = "dev.sinty.publish";
            wp.title = _("Books");
            wp.subtitle = _("Several publications numbered, styled, indexed and exported as one book");
            wp.add_action ("document-new", _("New Book"), _("Start a book file and add chapters"), () => {
                dlg.close ();
                create.begin (w);
            });
            wp.add_action ("document-open", _("Open Book"), _("Continue with an existing book file"), () => {
                dlg.close ();
                open_book (w);
            });
            box.append (wp);
            dlg.open_dialog ();
        }

        private static async void create (PublishWindow w) {
            var file = yield w.ask_save (_("New Book"), _("Book") + "." + Book.EXTENSION, { Book.EXTENSION }, _("Publish Book"));
            if (file == null) return;
            var b = new Book ();
            b.path = file.get_path ();
            b.name = file.get_basename ().replace ("." + Book.EXTENSION, "");
            if (w.doc != null && w.doc.path != null && w.doc.path != "") b.docs.add (new BookEntry (w.doc.path));
            try {
                b.save ();
            } catch (Error e) {
                w.show_error (_("Could Not Create the Book"), e.message);
                return;
            }
            current = b;
            manage (w, b);
        }

        public static void open_path (PublishWindow w, string path) {
            try {
                current = Book.load (path);
                var b = current;
                Timeout.add (400, () => {
                    manage (w, b);
                    return Source.REMOVE;
                });
            } catch (Error e) {
                w.show_error (_("Could Not Open the Book"), e.message);
            }
        }

        private static void open_book (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Open Book");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Publish Book"), { Book.EXTENSION }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            dialog.open.begin (w, null, (o, res) => {
                try {
                    var f = dialog.open.end (res);
                    if (f != null && f.get_path () != null) open_path (w, f.get_path ());
                } catch (Error e) {
                }
            });
        }

        private static void add_documents (PublishWindow w, Book b, AppDialog parent) {
            var dialog = new FileDialog ();
            dialog.title = _("Add Documents");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Publish Document"), { "spub" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            dialog.open_multiple.begin (w, null, (o, res) => {
                try {
                    var files = dialog.open_multiple.end (res);
                    for (uint i = 0; i < files.get_n_items (); i++) {
                        var f = files.get_item (i) as File;
                        if (f != null && f.get_path () != null) b.docs.add (new BookEntry (f.get_path ()));
                    }
                    b.save ();
                    parent.close ();
                    manage (w, b);
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) w.show_error (_("Could Not Add the Documents"), e.message);
                }
            });
        }

        private static void run (PublishWindow w, AppDialog dlg, Book b, string done) {
            try {
                b.save ();
            } catch (Error e) {
                w.show_error (_("Could Not Save the Book"), e.message);
                return;
            }
            w.toast (done);
            dlg.close ();
            manage (w, b);
        }

        public static void manage (PublishWindow w, Book b) {
            var dlg = Dialogs.make (w, b.name != "" ? b.name : _("Book"), 560, 720);
            var box = Dialogs.body (dlg);
            var dg = new PreferencesGroup (_("Documents"), _("In reading order; page numbers continue from one document to the next"));
            for (int i = 0; i < b.docs.size; i++) {
                int idx = i;
                var e = b.docs[i];
                string sub = Path.get_basename (Path.get_dirname (e.path));
                if (i == b.style_source) sub = _("Style source") + ", " + sub;
                if (!FileUtils.test (e.path, FileTest.EXISTS)) sub = _("Missing: %s").printf (e.path);
                var row = new SwitchRow (Path.get_basename (e.path), sub, e.include);
                var inc = row.switch_btn;
                inc.tooltip_text = _("Include in numbering and export");
                inc.notify["active"].connect (() => {
                    e.include = inc.active;
                    try {
                        b.save ();
                    } catch (Error err) {
                    }
                });
                var up = new Button.from_icon_name ("go-up-symbolic");
                up.add_css_class ("flat");
                up.valign = Align.CENTER;
                up.tooltip_text = _("Move Up");
                up.sensitive = i > 0;
                up.clicked.connect (() => {
                    var x = b.docs[idx];
                    b.docs.remove_at (idx);
                    b.docs.insert (idx - 1, x);
                    if (b.style_source == idx) b.style_source = idx - 1;
                    else if (b.style_source == idx - 1) b.style_source = idx;
                    run (w, dlg, b, _("Order changed; update the numbering"));
                });
                row.add_suffix (up);
                var open = new Button.from_icon_name ("document-open-symbolic");
                open.add_css_class ("flat");
                open.valign = Align.CENTER;
                open.tooltip_text = _("Open");
                open.clicked.connect (() => w.app.open_file (File.new_for_path (e.path), null));
                row.add_suffix (open);
                var src = new Button.from_icon_name ("object-select-symbolic");
                src.add_css_class ("flat");
                src.valign = Align.CENTER;
                src.tooltip_text = _("Use as Style Source");
                src.clicked.connect (() => {
                    b.style_source = idx;
                    run (w, dlg, b, _("Style source changed"));
                });
                row.add_suffix (src);
                var del = new Button.from_icon_name ("list-remove-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Remove from Book");
                del.clicked.connect (() => {
                    b.docs.remove_at (idx);
                    if (b.style_source >= b.docs.size) b.style_source = 0;
                    run (w, dlg, b, _("Document removed from the book"));
                });
                row.add_suffix (del);
                ((Box) inc.get_parent ()).remove (inc);
                row.add_suffix (inc);
                dg.add_row (row);
            }
            var add = new ActionRow (_("Add Documents"), _("Publish documents become chapters of the book"));
            var ab = new Button.with_label (_("Add…"));
            ab.valign = Align.CENTER;
            ab.clicked.connect (() => add_documents (w, b, dlg));
            add.add_suffix (ab);
            dg.add_row (add);
            box.append (dg);
            var og = new PreferencesGroup (_("Book Tasks"), _("Documents are saved after each task; reopen them to see the result"));
            var cont = new SwitchRow (_("Continuous Page Numbers"), _("Each document starts after the last page of the previous one"), b.continuous);
            cont.switch_btn.notify["active"].connect (() => b.continuous = cont.switch_btn.active);
            og.add_row (cont);
            task (og, _("Update Numbering"), null, () => {
                try {
                    int n = b.paginate ();
                    run (w, dlg, b, ngettext ("Numbered %d page", "Numbered %d pages", n).printf (n));
                } catch (Error e) {
                    w.show_error (_("Could Not Update the Numbering"), e.message);
                }
            });
            task (og, _("Synchronize Styles and Swatches"), _("From the style source to every other document"), () => {
                try {
                    int n = b.sync_styles ();
                    run (w, dlg, b, ngettext ("Synchronized %d document", "Synchronized %d documents", n).printf (n));
                } catch (Error e) {
                    w.show_error (_("Could Not Synchronize"), e.message);
                }
            });
            task (og, _("Book Table of Contents"), _("Written into the first document, from the heading styles of all chapters"), () => {
                try {
                    var first = b.open_doc (0);
                    var ts = first.toc != null ? first.toc.clone () : new TocSettings ();
                    if (ts.levels.size == 0) {
                        ts.title = _("Contents");
                        foreach (string h in new string[] { "Heading 1", "Heading 2" }) if (first.styles.find_paragraph (h) != null) ts.levels.add (new TocLevel (h, ts.levels.size + 1, ""));
                    }
                    int n = b.generate_toc (0, ts);
                    run (w, dlg, b, ngettext ("Contents with %d entry", "Contents with %d entries", n).printf (n));
                } catch (Error e) {
                    w.show_error (_("Could Not Create the Contents"), e.message);
                }
            });
            task (og, _("Book Index"), _("Written into the last document, from the index entries of all chapters"), () => {
                try {
                    int last = b.docs.size - 1;
                    var p = b.open_doc (last);
                    var ix = p.index != null ? p.index.clone () : new IndexSettings ();
                    if (p.index == null) ix.title = _("Index");
                    int n = b.generate_index (last, ix);
                    run (w, dlg, b, ngettext ("Index with %d topic", "Index with %d topics", n).printf (n));
                } catch (Error e) {
                    w.show_error (_("Could Not Create the Index"), e.message);
                }
            });
            task (og, _("Export Book as PDF"), _("All included documents in one file"), () => export.begin (w, b));
            box.append (og);
            dlg.open_dialog ();
        }

        private static void task (PreferencesGroup g, string title, string? subtitle, owned Dialogs.Apply f) {
            var row = new ActionRow (title, subtitle);
            var btn = new Button.with_label (_("Run"));
            btn.valign = Align.CENTER;
            btn.clicked.connect (() => f ());
            row.add_suffix (btn);
            g.add_row (row);
        }

        private static async void export (PublishWindow w, Book b) {
            var file = yield w.ask_save (_("Export Book"), (b.name != "" ? b.name : _("Book")) + ".pdf", { "pdf" }, _("PDF Document"));
            if (file == null) return;
            try {
                var o = new ExportOptions ();
                int n = b.export_pdf (file.get_path (), o);
                w.toast (ngettext ("Exported %d page", "Exported %d pages", n).printf (n));
            } catch (Error e) {
                w.show_error (_("Could Not Export the Book"), e.message);
            }
        }
    }
}
