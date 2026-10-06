using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class FindDialog {
        private PublishWindow w;
        private AppDialog dlg;
        private Stack stack;
        private EntryRow find;
        private EntryRow change;
        private SwitchRow case_row;
        private SwitchRow word_row;
        private SwitchRow text_row;
        private SelectionRow f_para;
        private SelectionRow f_char;
        private SelectionRow f_bold;
        private SelectionRow f_italic;
        private SelectionRow c_para;
        private SelectionRow c_char;
        private SelectionRow c_bold;
        private SelectionRow c_italic;
        private SelectionRow o_kind;
        private EntryRow o_fill;
        private SelectionRow o_style;
        private SelectionRow o_change_style;
        private EntryRow o_change_fill;
        private Label status;
        private string mode = "text";
        private int index = -1;
        private string[] any_para;
        private string[] any_char;
        private string[] tri;
        private string[] kinds;
        private string[] ostyles;

        public static void open (PublishWindow w) {
            new FindDialog (w).dlg.open_dialog ();
        }

        private static PreferencesGroup group (Box box, string title, string? desc = null) {
            var g = new PreferencesGroup (title, desc);
            box.append (g);
            return g;
        }

        private FindDialog (PublishWindow w) {
            this.w = w;
            var pub = w.doc.pub;
            dlg = Dialogs.make (w, _("Find and Change"), 520, 700);
            var sw = new BubbleSwitcher ();
            sw.halign = Align.CENTER;
            sw.margin_top = 6;
            sw.add_option ("text", _("Text"));
            sw.add_option ("grep", _("GREP"));
            sw.add_option ("object", _("Object"));
            sw.set_active ("text");
            dlg.content_box.append (sw);
            stack = new Stack ();
            stack.vexpand = true;
            dlg.content_box.append (stack);
            any_para = { _("Any") };
            foreach (var s in pub.styles.paragraph) any_para += s.name;
            any_char = { _("Any") };
            foreach (var s in pub.styles.character) any_char += s.name;
            tri = { _("Any"), _("On"), _("Off") };
            var tbox = new Box (Orientation.VERTICAL, 14);
            tbox.margin_start = tbox.margin_end = 18;
            tbox.margin_top = 6;
            var tg = group (tbox, _("Search"));
            find = new EntryRow (_("Find What"));
            find.text = w.canvas.selected_text ().contains ("\n") ? "" : w.canvas.selected_text ();
            tg.add_row (find);
            change = new EntryRow (_("Change To"));
            change.tooltip_text = _("With GREP, $1 to $9 insert the matched groups");
            tg.add_row (change);
            text_row = new SwitchRow (_("Change the Text"), _("Switch off to change only the formatting"), true);
            tg.add_row (text_row);
            case_row = new SwitchRow (_("Match Case"), null, w.find_case);
            tg.add_row (case_row);
            word_row = new SwitchRow (_("Whole Words Only"), null, w.find_word);
            tg.add_row (word_row);
            var fg = group (tbox, _("Find Format"), _("Only text with this formatting is found; leave the text empty to find by formatting alone"));
            f_para = new SelectionRow (_("Paragraph Style"), any_para, any_para[0]);
            fg.add_row (f_para);
            f_char = new SelectionRow (_("Character Style"), any_char, any_char[0]);
            fg.add_row (f_char);
            f_bold = new SelectionRow (_("Bold"), tri, tri[0]);
            fg.add_row (f_bold);
            f_italic = new SelectionRow (_("Italic"), tri, tri[0]);
            fg.add_row (f_italic);
            var cg = group (tbox, _("Change Format"));
            c_para = new SelectionRow (_("Paragraph Style"), any_para, any_para[0]);
            cg.add_row (c_para);
            c_char = new SelectionRow (_("Character Style"), any_char, any_char[0]);
            cg.add_row (c_char);
            c_bold = new SelectionRow (_("Bold"), tri, tri[0]);
            cg.add_row (c_bold);
            c_italic = new SelectionRow (_("Italic"), tri, tri[0]);
            cg.add_row (c_italic);
            var tscroll = new ScrolledWindow ();
            tscroll.hscrollbar_policy = PolicyType.NEVER;
            tscroll.child = tbox;
            stack.add_named (tscroll, "text");
            kinds = { _("Any"), _("Text Frame"), _("Image Frame"), _("Shape"), _("Table"), _("Group") };
            ostyles = { _("Any") };
            foreach (var o in pub.object_styles) ostyles += o.name;
            var obox = new Box (Orientation.VERTICAL, 14);
            obox.margin_start = obox.margin_end = 18;
            obox.margin_top = 6;
            var og = group (obox, _("Find Objects"));
            o_kind = new SelectionRow (_("Kind"), kinds, kinds[0]);
            og.add_row (o_kind);
            o_fill = new EntryRow (_("Fill Colour"));
            o_fill.tooltip_text = _("A colour such as #ff0000 or a swatch name");
            og.add_row (o_fill);
            o_style = new SelectionRow (_("Object Style"), ostyles, ostyles[0]);
            og.add_row (o_style);
            var ocg = group (obox, _("Change Objects"));
            string[] keep = { _("Keep") };
            foreach (var o in pub.object_styles) keep += o.name;
            o_change_style = new SelectionRow (_("Object Style"), keep, keep[0]);
            ocg.add_row (o_change_style);
            o_change_fill = new EntryRow (_("Fill Colour"));
            ocg.add_row (o_change_fill);
            stack.add_named (obox, "object");
            sw.selected.connect ((name) => {
                mode = name;
                index = -1;
                stack.visible_child_name = name == "object" ? "object" : "text";
                word_row.visible = name == "text";
                status.label = "";
            });
            status = new Label ("");
            status.add_css_class ("dim-label");
            status.margin_start = 18;
            status.xalign = 0;
            dlg.content_box.append (status);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 8;
            var next = new Button.with_label (_("Find Next"));
            next.clicked.connect (() => find_next ());
            bar.append (next);
            var sp = new Box (Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append (sp);
            var one = new Button.with_label (_("Change"));
            one.clicked.connect (() => change_one ());
            bar.append (one);
            var all = new Button.with_label (_("Change All"));
            all.add_css_class ("suggested-action");
            all.clicked.connect (() => change_all ());
            bar.append (all);
            dlg.content_box.append (bar);
        }

        private static string? nullable (string v) {
            string s = v.strip ();
            if (s == "") return null;
            if (s.has_prefix ("#") || s.has_prefix ("swatch:") || s.has_prefix ("cmyk:")) return s;
            return ColorRef.swatch (s);
        }

        private int tri_value (SelectionRow r) {
            if (r.current_value == tri[1]) return 1;
            if (r.current_value == tri[2]) return 0;
            return -1;
        }

        private FindQuery query () {
            var q = new FindQuery ();
            q.pattern = find.text;
            q.grep = mode == "grep";
            q.match_case = case_row.switch_btn.active;
            q.whole_word = mode == "text" && word_row.switch_btn.active;
            q.change_text = text_row.switch_btn.active;
            q.replacement = change.text;
            q.find_fmt.para_style = f_para.current_value == any_para[0] ? "" : f_para.current_value;
            q.find_fmt.char_style = f_char.current_value == any_char[0] ? "" : f_char.current_value;
            q.find_fmt.bold = tri_value (f_bold);
            q.find_fmt.italic = tri_value (f_italic);
            q.change_fmt.para_style = c_para.current_value == any_para[0] ? "" : c_para.current_value;
            q.change_fmt.char_style = c_char.current_value == any_char[0] ? "" : c_char.current_value;
            q.change_fmt.bold = tri_value (c_bold);
            q.change_fmt.italic = tri_value (c_italic);
            w.find_case = q.match_case;
            w.find_word = q.whole_word;
            return q;
        }

        private ObjectQuery object_query () {
            var q = new ObjectQuery ();
            for (int i = 1; i < kinds.length; i++) if (o_kind.current_value == kinds[i]) q.kind = i - 1;
            q.fill = nullable (o_fill.text) ?? "";
            q.object_style = o_style.current_value == ostyles[0] ? "" : o_style.current_value;
            q.change_object_style = o_change_style.current_value == _("Keep") ? "" : o_change_style.current_value;
            q.change_fill = nullable (o_change_fill.text) ?? "";
            return q;
        }

        private Gee.ArrayList<FindMatch>? matches (FindQuery q) {
            var list = new Gee.ArrayList<FindMatch> ();
            if (q.pattern == "" && q.find_fmt.is_empty ()) return list;
            try {
                foreach (var s in w.stories_for_find ()) list.add_all (Finder.search (w.doc.pub, s, q));
            } catch (RegexError e) {
                status.label = _("The expression is not valid: %s").printf (e.message);
                return null;
            }
            return list;
        }

        private void find_next () {
            if (mode == "object") {
                var found = Finder.find_objects (w.doc.pub, object_query ());
                status.label = ngettext ("%d object found", "%d objects found", found.size).printf (found.size);
                if (found.size > 0) {
                    index = (index + 1) % found.size;
                    w.select_item_public (found[index]);
                }
                return;
            }
            var list = matches (query ());
            if (list == null) return;
            if (list.size == 0) {
                status.label = _("Not found");
                return;
            }
            index = (index + 1) % list.size;
            var m = list[index];
            w.focus_match (m.story, m.a, m.b.offset - m.a.offset);
            status.label = _("%d of %d").printf (index + 1, list.size);
        }

        private void change_one () {
            if (mode == "object") {
                change_all ();
                return;
            }
            var q = query ();
            var list = matches (q);
            if (list == null || list.size == 0) {
                status.label = _("Not found");
                return;
            }
            int i = index < 0 ? 0 : index.clamp (0, list.size - 1);
            var m = list[i];
            w.canvas.end_edit ();
            w.edit (_("Change"), () => Finder.replace_match (w.doc.pub, m, q));
            index = i - 1;
            find_next ();
        }

        private void change_all () {
            w.canvas.end_edit ();
            if (mode == "object") {
                int n = 0;
                var oq = object_query ();
                w.edit (_("Change All"), () => n = Finder.change_objects (w.doc.pub, oq));
                status.label = ngettext ("Changed %d object", "Changed %d objects", n).printf (n);
                return;
            }
            var q = query ();
            int total = 0;
            string err = "";
            w.edit (_("Change All"), () => {
                try {
                    total = Finder.replace_all (w.doc.pub, w.stories_for_find (), q);
                } catch (RegexError e) {
                    err = e.message;
                }
            });
            status.label = err != "" ? _("The expression is not valid: %s").printf (err) : ngettext ("Changed %d occurrence", "Changed %d occurrences", total).printf (total);
            index = -1;
        }
    }
}
