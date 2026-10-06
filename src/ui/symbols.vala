using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class SymbolDialog {
        private static Gee.ArrayList<string>? recent = null;

        private struct Block {
            public string name;
            public uint start;
            public uint end;
        }

        private static Block[] blocks () {
            return {
                { _("Latin"), 0x0020, 0x007E },
                { _("Latin-1 Supplement"), 0x00A0, 0x00FF },
                { _("Latin Extended-A"), 0x0100, 0x017F },
                { _("Latin Extended-B"), 0x0180, 0x024F },
                { _("Spacing Modifier Letters"), 0x02B0, 0x02FF },
                { _("Greek and Coptic"), 0x0370, 0x03FF },
                { _("Cyrillic"), 0x0400, 0x04FF },
                { _("Hebrew"), 0x0590, 0x05FF },
                { _("Arabic"), 0x0600, 0x06FF },
                { _("General Punctuation"), 0x2000, 0x206F },
                { _("Superscripts and Subscripts"), 0x2070, 0x209F },
                { _("Currency Symbols"), 0x20A0, 0x20CF },
                { _("Letterlike Symbols"), 0x2100, 0x214F },
                { _("Number Forms"), 0x2150, 0x218F },
                { _("Arrows"), 0x2190, 0x21FF },
                { _("Mathematical Operators"), 0x2200, 0x22FF },
                { _("Miscellaneous Technical"), 0x2300, 0x23FF },
                { _("Enclosed Alphanumerics"), 0x2460, 0x24FF },
                { _("Box Drawing"), 0x2500, 0x257F },
                { _("Block Elements"), 0x2580, 0x259F },
                { _("Geometric Shapes"), 0x25A0, 0x25FF },
                { _("Miscellaneous Symbols"), 0x2600, 0x26FF },
                { _("Dingbats"), 0x2700, 0x27BF },
                { _("Alphabetic Presentation Forms"), 0xFB00, 0xFB4F },
                { _("Pictographs"), 0x1F300, 0x1F5FF },
                { _("Emoticons"), 0x1F600, 0x1F64F }
            };
        }

        public static void open (PublishWindow w) {
            if (recent == null) recent = new Gee.ArrayList<string> ();
            string family = w.current_chars ().font ?? "Inter";
            var dlg = Dialogs.make (w, _("Symbol"), 640, 680);
            var outer = new Box (Orientation.VERTICAL, 10);
            outer.margin_start = outer.margin_end = 18;
            outer.margin_top = 6;
            outer.vexpand = true;
            var top = new PreferencesGroup (null);
            var bl = blocks ();
            string[] names = new string[bl.length];
            for (int i = 0; i < bl.length; i++) names[i] = bl[i].name;
            var block_row = new SelectionRow (_("Subset"), names, names[1]);
            top.add_row (block_row);
            var font_row = new EntryRow (_("Font"));
            font_row.text = family;
            top.add_row (font_row);
            var code = new EntryRow (_("Character Code"));
            code.tooltip_text = _("Type a hexadecimal code such as 00A9 or U+2122 and press Enter");
            top.add_row (code);
            outer.append (top);
            var recent_box = new Box (Orientation.HORIZONTAL, 4);
            outer.append (recent_box);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.SINGLE;
            flow.activate_on_single_click = false;
            flow.max_children_per_line = 16;
            flow.min_children_per_line = 8;
            flow.homogeneous = true;
            flow.column_spacing = 2;
            flow.row_spacing = 2;
            flow.valign = Align.START;
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = flow;
            outer.append (scroll);
            var info = new Label ("");
            info.add_css_class ("dim-label");
            info.xalign = 0;
            outer.append (info);
            dlg.content_box.append (outer);
            var chars = new Gee.ArrayList<string> ();
            ProDialogs.Done insert_selected = null;
            insert_selected = () => {
                var selc = flow.get_selected_children ();
                if (selc.length () == 0) return;
                string ch = chars[selc.data.get_index ()];
                if (w.canvas.edit == null) {
                    w.toast (_("Click in a text frame first"));
                    return;
                }
                w.canvas.insert_text (ch);
                recent.remove (ch);
                recent.insert (0, ch);
                while (recent.size > 16) recent.remove_at (recent.size - 1);
            };
            ProDialogs.Done fill = null;
            fill = () => {
                Widget? c;
                while ((c = flow.get_first_child ()) != null) flow.remove (c);
                chars.clear ();
                var fd = new Pango.FontDescription ();
                fd.set_family (font_row.text.strip () != "" ? font_row.text.strip () : "Inter");
                fd.set_absolute_size (20 * Pango.SCALE);
                var font = TextEngine.context ().load_font (fd);
                Block? blk = null;
                foreach (var b in bl) if (b.name == block_row.current_value) blk = b;
                if (blk == null) return;
                for (uint u = blk.start; u <= blk.end; u++) {
                    unichar uc = (unichar) u;
                    if (!uc.validate () || uc.iscntrl () || uc.type () == UnicodeType.UNASSIGNED) continue;
                    if (font != null && !font.has_char (uc)) continue;
                    string s = uc.to_string ();
                    chars.add (s);
                    var l = new Label (null);
                    l.set_markup ("<span font_family=\"%s\" size=\"x-large\">%s</span>".printf (Markup.escape_text (fd.get_family ()), Markup.escape_text (s)));
                    l.tooltip_text = "U+%04X".printf (u);
                    l.set_size_request (32, 36);
                    flow.append (l);
                }
                info.label = ngettext ("%d character", "%d characters", chars.size).printf (chars.size);
                Widget? rc;
                while ((rc = recent_box.get_first_child ()) != null) recent_box.remove (rc);
                if (recent.size > 0) {
                    var rl = new Label (_("Recent"));
                    rl.add_css_class ("dim-label");
                    recent_box.append (rl);
                    foreach (string r in recent) {
                        string rs = r;
                        var b = new Button.with_label (rs);
                        b.add_css_class ("flat");
                        b.clicked.connect (() => {
                            if (w.canvas.edit != null) w.canvas.insert_text (rs);
                            else w.toast (_("Click in a text frame first"));
                        });
                        recent_box.append (b);
                    }
                }
            };
            block_row.selected.connect ((item) => fill ());
            font_row.entry_activated.connect (() => fill ());
            code.entry_activated.connect (() => {
                string t = code.text.strip ().up ().replace ("U+", "").replace ("0X", "");
                uint64 v;
                if (!uint64.try_parse (t, out v, null, 16)) return;
                foreach (var b in bl) {
                    if (v >= b.start && v <= b.end) {
                        block_row.current_value = b.name;
                        fill ();
                        string target = ((unichar) v).to_string ();
                        int idx = chars.index_of (target);
                        if (idx >= 0) flow.select_child (flow.get_child_at_index (idx));
                        return;
                    }
                }
                if (w.canvas.edit != null) w.canvas.insert_text (((unichar) v).to_string ());
            });
            flow.child_activated.connect ((child) => insert_selected ());
            fill ();
            Dialogs.footer (dlg, _("Insert"), () => insert_selected (), false);
            dlg.open_dialog ();
        }
    }
}
