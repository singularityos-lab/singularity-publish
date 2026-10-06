using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class WindowMacroHost : MacroHost {
        private PublishWindow w;

        public WindowMacroHost (PublishWindow w) {
            this.w = w;
        }

        public override Publication publication () {
            return w.doc.pub;
        }

        public override bool run_action (string name, string? param) {
            var a = w.lookup_action (name);
            if (a == null) return false;
            if (a.parameter_type != null && param == null) return false;
            if (a.parameter_type == null) a.activate (null);
            else a.activate (new Variant.string (param));
            return true;
        }

        public override void insert_text (string text) {
            if (w.canvas.edit == null) {
                var t = w.single_text_frame ();
                if (t == null) return;
                w.canvas.begin_edit (t);
            }
            w.canvas.insert_text (text);
        }

        public override void go_to_page (int index) {
            w.go_to_page (index);
        }

        public override void select_items (Gee.List<Item> items) {
            w.canvas.end_edit ();
            w.canvas.selection.clear ();
            w.canvas.selection.add_all (items);
            w.canvas.selection_changed ();
        }

        public override Gee.List<Item> page_items (int index) {
            var l = new Gee.ArrayList<Item> ();
            if (index >= 0 && index < w.doc.pub.pages.size) l.add_all (w.doc.pub.pages[index].items);
            return l;
        }

        public override void format_chars (string key, string value) {
            switch (key) {
                case "font":
                    w.format_runs (_("Font"), (r) => r.fmt.font = value);
                    break;
                case "size":
                    double v = Units.parse_num (value, 11);
                    w.format_runs (_("Font Size"), (r) => r.fmt.size = v);
                    break;
                case "color":
                    string spec = value.has_prefix ("#") || value.has_prefix ("swatch:") || value.has_prefix ("cmyk:") ? value : ColorRef.swatch (value);
                    w.format_runs (_("Text Colour"), (r) => r.fmt.color = spec);
                    break;
                case "bold":
                    int b = int.parse (value);
                    w.format_runs (_("Bold"), (r) => r.fmt.bold = b);
                    break;
                case "italic":
                    int i = int.parse (value);
                    w.format_runs (_("Italic"), (r) => r.fmt.italic = i);
                    break;
                case "underline":
                    int u = int.parse (value);
                    w.format_runs (_("Underline"), (r) => r.fmt.underline = u);
                    break;
            }
        }

        public override void apply_style (string name) {
            w.format_paras (_("Paragraph Style"), (p) => p.style = name);
        }

        public override void export_pdf (string path) throws Error {
            string p = Path.is_absolute (path) ? path : Path.build_filename (w.default_folder ().get_path (), path);
            var ex = new Exporter (w.doc.pub, new ExportOptions ());
            ex.export_pdf (p);
        }

        public override void changed () {
            w.content_edited ();
            w.pages_panel.load ();
        }

        public override void message (string text) {
            w.toast (text);
        }
    }

    public class MacrosUi {
        private static bool firing = false;

        public static void fire (PublishWindow w, string ev) {
            if (firing || w.doc == null) return;
            var m = MacroEngine.for_event (w.doc.pub, ev);
            if (m == null) return;
            firing = true;
            try {
                new MacroEngine ().run (new WindowMacroHost (w), m.script);
            } catch (Error e) {
                w.show_error (_("The Macro \"%s\" Stopped").printf (m.name), e.message);
            }
            firing = false;
        }

        public static void before_action (PublishWindow w, string name) {
            if (name == "save" || name == "save-as") fire (w, "save");
            else if (name == "print") fire (w, "print");
            else if (name.has_prefix ("export-")) fire (w, "export");
        }

        public static void after_action (PublishWindow w, string name) {
            if (name == "add-page" || name == "insert-pages" || name == "duplicate-page") fire (w, "new-page");
        }

        public static void document_opened (PublishWindow w) {
            w.macro_banner.visible = false;
            if (w.doc == null) return;
            var m = MacroEngine.for_event (w.doc.pub, "open");
            if (m == null) return;
            w.macro_banner.title = _("This publication runs the macro \"%s\" when it opens. Run it only if you trust where the file came from.").printf (m.name);
            w.macro_banner.visible = true;
        }

        public static void run_macro (PublishWindow w, MacroDef m) {
            var engine = new MacroEngine ();
            try {
                int steps = engine.run (new WindowMacroHost (w), m.script);
                w.toast (ngettext ("Ran \"%s\" in %d step", "Ran \"%s\" in %d steps", steps).printf (m.name, steps));
            } catch (Error e) {
                w.show_error (_("The Macro Stopped"), e.message);
            }
        }

        public static void toggle_record (PublishWindow w) {
            if (w.recording == null) {
                w.recording = new StringBuilder ();
                var t = new Toast (_("Recording a macro. Choose Stop Recording when you are done"));
                t.timeout = 4;
                w.add_toast (t);
                return;
            }
            string script = w.recording.str;
            w.recording = null;
            if (script.strip () == "") {
                w.toast (_("Nothing was recorded"));
                return;
            }
            edit (w, new MacroDef (_("Recorded Macro"), script), true, false);
        }

        public static void edit (PublishWindow w, MacroDef m, bool is_new, bool in_library) {
            var dlg = Dialogs.make (w, is_new ? _("New Macro") : _("Edit Macro"), 560, 640);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null);
            var name = new EntryRow (_("Name"));
            name.text = m.name;
            g.add_row (name);
            var lib = new SwitchRow (_("Available in All Publications"), _("Otherwise the macro is saved inside this publication"), in_library);
            g.add_row (lib);
            string[] evs = { "" };
            foreach (string e in MacroEngine.events ()) evs += e;
            string[] ev_labels = {};
            foreach (string e in evs) ev_labels += MacroEngine.event_label (e);
            string current_label = MacroEngine.event_label (m.event);
            var ev_row = new SelectionRow (_("Runs"), ev_labels, current_label);
            ev_row.subtitle = _("Document events work for macros saved inside this publication");
            g.add_row (ev_row);
            box.append (g);
            var tv = new TextView ();
            tv.monospace = true;
            tv.wrap_mode = Gtk.WrapMode.NONE;
            tv.buffer.text = m.script;
            tv.top_margin = tv.bottom_margin = tv.left_margin = tv.right_margin = 8;
            var sw = new ScrolledWindow ();
            sw.min_content_height = 240;
            sw.vexpand = true;
            sw.child = tv;
            sw.add_css_class ("card");
            box.append (sw);
            var help = new Label (_("One command per line. Editing: action NAME, type TEXT, page N, replace \"old\" \"new\" [case] [word], font, size, color, bold, italic, underline, style NAME, new-page, export-pdf FILE, save, message TEXT. Variables and logic: set NAME = EXPRESSION, if ... elif ... else ... end, while ... end, for NAME from A to B ... end, repeat N ... end, break. Objects: for-each-page, for-each-item [text|image|shape|table], for-each-paragraph, set-item PROPERTY VALUE, set-paragraph style|align|text VALUE, define-style NAME PROPERTY VALUE, add-text-frame X Y W H TEXT, add-shape KIND X Y W H COLOUR, delete-item. Expressions use item.name, item.text, item.x, paragraph.text, page.number, pages.count, len(), upper(), contains(), count(); write {expression} inside other commands. Lines starting with # are skipped."));
            help.wrap = true;
            help.xalign = 0;
            help.add_css_class ("caption");
            help.add_css_class ("dim-label");
            box.append (help);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip () != "" ? name.text.strip () : _("Macro");
                string script = tv.buffer.text;
                try {
                    MacroEngine.parse (script);
                } catch (Error e) {
                    w.show_error (_("The Macro Has an Error"), e.message);
                    return;
                }
                var def = new MacroDef (n, script);
                for (int k = 0; k < evs.length; k++) if (ev_labels[k] == ev_row.current_value) def.event = evs[k];
                if (lib.switch_btn.active) {
                    try {
                        MacroEngine.save_to_library (def);
                    } catch (Error e) {
                        w.show_error (_("Could Not Save the Macro"), e.message);
                    }
                    if (!is_new && !in_library) w.edit (_("Move Macro"), () => w.doc.pub.macros.remove (m));
                } else {
                    w.edit (_("Save Macro"), () => {
                        MacroDef? old = null;
                        foreach (var x in w.doc.pub.macros) if (x.name == n || x == m) old = x;
                        if (old != null) w.doc.pub.macros.remove (old);
                        w.doc.pub.macros.add (def);
                    });
                    if (!is_new && in_library) {
                        try {
                            MacroEngine.remove_from_library (m.name);
                        } catch (Error e) {
                        }
                    }
                }
                w.toast (_("Saved the macro \"%s\"").printf (n));
            });
            dlg.open_dialog ();
        }

        public static void manager (PublishWindow w) {
            var dlg = Dialogs.make (w, _("Macros"), 560, 620);
            var box = Dialogs.body (dlg);
            var doc_list = w.doc.pub.macros;
            var lib_list = MacroEngine.library ();
            if (doc_list.size == 0 && lib_list.size == 0) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                wp.title = _("No Macros");
                wp.subtitle = _("Record your steps or write a macro to repeat work across pages and publications");
                wp.add_action ("media-record", _("Record a Macro"), _("Repeat what you do next"), () => {
                    dlg.close ();
                    toggle_record (w);
                });
                wp.add_action ("document-new", _("Write a Macro"), _("Start from a short example"), () => {
                    dlg.close ();
                    edit (w, new MacroDef (_("New Macro"), "message \"%s\"\n".printf (_("Hello from a macro"))), true, false);
                });
                box.append (wp);
            }
            for (int pass = 0; pass < 2; pass++) {
                var list = pass == 0 ? doc_list : lib_list;
                if (list.size == 0) continue;
                var g = new PreferencesGroup (pass == 0 ? _("In This Publication") : _("In All Publications"));
                foreach (var m in list) {
                    var macro = m;
                    bool in_lib = pass == 1;
                    int lines = 0;
                    foreach (string l in macro.script.split ("\n")) if (l.strip () != "" && !l.strip ().has_prefix ("#")) lines++;
                    var row = new ActionRow (macro.name, ngettext ("%d command", "%d commands", lines).printf (lines));
                    var run = new Button.with_label (_("Run"));
                    run.valign = Align.CENTER;
                    run.add_css_class ("suggested-action");
                    run.clicked.connect (() => {
                        dlg.close ();
                        run_macro (w, macro);
                    });
                    var ed = new Button.from_icon_name ("document-edit-symbolic");
                    ed.add_css_class ("flat");
                    ed.valign = Align.CENTER;
                    ed.tooltip_text = _("Edit");
                    ed.clicked.connect (() => {
                        dlg.close ();
                        edit (w, macro, false, in_lib);
                    });
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete");
                    del.clicked.connect (() => {
                        if (in_lib) {
                            try {
                                MacroEngine.remove_from_library (macro.name);
                            } catch (Error e) {
                            }
                        } else {
                            w.edit (_("Delete Macro"), () => w.doc.pub.macros.remove (macro));
                        }
                        dlg.close ();
                        manager (w);
                    });
                    row.add_suffix (run);
                    row.add_suffix (ed);
                    row.add_suffix (del);
                    g.add_row (row);
                }
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var rec = new Button.with_label (w.recording == null ? _("Record…") : _("Stop Recording"));
            rec.clicked.connect (() => {
                dlg.close ();
                toggle_record (w);
            });
            bar.append (rec);
            var nw = new Button.with_label (_("New Macro…"));
            nw.clicked.connect (() => {
                dlg.close ();
                edit (w, new MacroDef (_("New Macro"), "message \"%s\"\n".printf (_("Hello from a macro"))), true, false);
            });
            bar.append (nw);
            var sp2 = new Box (Orientation.HORIZONTAL, 0);
            sp2.hexpand = true;
            bar.append (sp2);
            bar.append (dlg.add_cancel_button (_("Close")));
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }
    }
}
