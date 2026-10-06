namespace Singularity.Apps.Publish {

    public enum FormKind {
        NONE,
        TEXT,
        CHECKBOX,
        BUTTON,
        CHOICE;

        public static string[] labels () {
            return { _("None"), _("Text Field"), _("Check Box"), _("Button"), _("Drop-down List") };
        }
    }

    public class FormSpec {
        public FormKind kind = FormKind.NONE;
        public string name = "";
        public string tooltip = "";
        public string options = "";
        public string action = "";
        public bool required = false;
        public bool multiline = false;

        public FormSpec clone () {
            var f = new FormSpec ();
            f.kind = kind;
            f.name = name;
            f.tooltip = tooltip;
            f.options = options;
            f.action = action;
            f.required = required;
            f.multiline = multiline;
            return f;
        }

        public void write (XmlOut x) {
            x.start ("form").ai ("kind", (int) kind).a ("name", name).a ("tooltip", tooltip).a ("options", options).a ("action", action).ai ("required", required ? 1 : 0).ai ("multiline", multiline ? 1 : 0).end ();
        }

        public static FormSpec? read (Xml.Node* n) {
            var c = XmlIn.child (n, "form");
            if (c == null) return null;
            var f = new FormSpec ();
            f.kind = (FormKind) XmlIn.int_attr (c, "kind", 0).clamp (0, 4);
            f.name = XmlIn.attr (c, "name") ?? "";
            f.tooltip = XmlIn.attr (c, "tooltip") ?? "";
            f.options = XmlIn.attr (c, "options") ?? "";
            f.action = XmlIn.attr (c, "action") ?? "";
            f.required = XmlIn.int_attr (c, "required", 0) == 1;
            f.multiline = XmlIn.int_attr (c, "multiline", 0) == 1;
            return f;
        }
    }

    public class PageTransition {
        public static string[] styles () {
            return { "", "Dissolve", "Fade", "Wipe", "Split", "Blinds", "Box", "Glitter", "Fly", "Push", "Cover", "Uncover" };
        }

        public static string[] labels () {
            return { _("None"), _("Dissolve"), _("Fade"), _("Wipe"), _("Split"), _("Blinds"), _("Box"), _("Glitter"), _("Fly"), _("Push"), _("Cover"), _("Uncover") };
        }
    }

    public class PdfFinish {
        public static string role_for (Publication pub, Paragraph p) {
            for (var st = pub.styles.find_paragraph (p.style); st != null; st = st.based_on != "" ? pub.styles.find_paragraph (st.based_on) : null) {
                if (st.tag != "") return st.tag;
                if (st.name == StyleSheet.BASIC) break;
            }
            string n = p.style.down ();
            if (n.contains ("title") && !n.contains ("sub")) return "H1";
            for (int lv = 1; lv <= 6; lv++) if (n.contains ("heading %d".printf (lv)) || n.contains ("head %d".printf (lv)) || n.contains ("h%d".printf (lv))) return "H%d".printf (lv);
            if (n.contains ("head")) return "H2";
            if (n.contains ("caption")) return "Caption";
            if (n.contains ("quote")) return "BlockQuote";
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (p.style, pf, cf);
            pf.apply (p.fmt);
            if (pf.list_type > 0) return "LI";
            return "P";
        }

        public class Placement {
            public int pdf_page;
            public double x;
            public double y;
            public double scale;
            public double sheet_h;
        }

        public static Gee.HashMap<int, Placement> placements (Gee.List<Sheet> sheets) {
            var map = new Gee.HashMap<int, Placement> ();
            for (int i = 0; i < sheets.size; i++) {
                foreach (var s in sheets[i].slots) {
                    if (map.has_key (s.page)) continue;
                    var pl = new Placement ();
                    pl.pdf_page = i;
                    pl.x = s.x;
                    pl.y = s.y;
                    pl.scale = s.scale;
                    pl.sheet_h = sheets[i].h;
                    map[s.page] = pl;
                }
            }
            return map;
        }

        public static bool needs (Publication pub, ExportOptions opts) {
            if (opts.tagged) return true;
            foreach (var pg in pub.pages) if (pg.transition != "") return true;
            bool forms = false;
            pub.walk ((r) => {
                if (r.item.form != null && r.item.form.kind != FormKind.NONE) forms = true;
                return !forms;
            });
            return forms;
        }

        public static void apply (string path, Publication pub, ExportOptions opts, Gee.List<Sheet> sheets, Gee.List<string> alts) throws Error {
            if (!needs (pub, opts)) return;
            var doc = Singularity.Pdf.Document.open_file (path);
            doc.load_all ();
            var cat = doc.catalog ();
            var place = placements (sheets);
            if (opts.tagged) {
                var mi = Singularity.Pdf.Obj.dictionary ();
                mi.set ("Marked", Singularity.Pdf.Obj.boolean (true));
                cat.set ("MarkInfo", mi);
                string lang = "en";
                var basic = pub.styles.find_paragraph (StyleSheet.BASIC);
                if (basic != null && basic.chars.lang != null && basic.chars.lang != "") lang = basic.chars.lang.replace ("_", "-");
                cat.set ("Lang", Singularity.Pdf.Obj.text (lang));
                wrap_document (doc, cat);
                var vp = Singularity.Pdf.Obj.dictionary ();
                vp.set ("DisplayDocTitle", Singularity.Pdf.Obj.boolean (true));
                cat.set ("ViewerPreferences", vp);
                int fig = 0;
                foreach (var node in Singularity.Pdf.Tags.read (doc)) {
                    if (node.role != "Figure") continue;
                    if (fig < alts.size && alts[fig] != "") Singularity.Pdf.Tags.set_alt (doc, node, alts[fig]);
                    fig++;
                }
            }
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var pg = pub.pages[pi];
                if (pg.transition == "" || !place.has_key (pi)) continue;
                var tr = Singularity.Pdf.Obj.dictionary ();
                tr.set ("Type", Singularity.Pdf.Obj.name_obj ("Trans"));
                tr.set ("S", Singularity.Pdf.Obj.name_obj (pg.transition == "Dissolve" || pg.transition == "Fade" || pg.transition == "Wipe" || pg.transition == "Split" || pg.transition == "Blinds" || pg.transition == "Box" || pg.transition == "Glitter" || pg.transition == "Fly" || pg.transition == "Push" || pg.transition == "Cover" || pg.transition == "Uncover" ? pg.transition : "R"));
                tr.set ("D", Singularity.Pdf.Obj.number (double.max (0.1, pg.transition_duration)));
                doc.page (place[pi].pdf_page).set ("Trans", tr);
            }
            var fields = new Gee.ArrayList<ItemRef> ();
            pub.walk ((r) => {
                if (r.page != null && r.item.form != null && r.item.form.kind != FormKind.NONE) fields.add (r);
                return true;
            });
            int auto_n = 1;
            foreach (var r in fields) {
                int pi = pub.pages.index_of (r.page);
                if (!place.has_key (pi)) continue;
                var pl = place[pi];
                var b = r.item.bounds ();
                double x1 = pl.x + b.x * pl.scale, x2 = pl.x + (b.x + b.w) * pl.scale;
                double y1 = pl.sheet_h - (pl.y + (b.y + b.h) * pl.scale), y2 = pl.sheet_h - (pl.y + b.y * pl.scale);
                var f = r.item.form;
                string name = f.name != "" ? f.name : (r.item.name != "" ? r.item.name : "Field%d".printf (auto_n++));
                Singularity.Pdf.FieldType type;
                switch (f.kind) {
                    case FormKind.TEXT: type = Singularity.Pdf.FieldType.TEXT; break;
                    case FormKind.CHECKBOX: type = Singularity.Pdf.FieldType.CHECKBOX; break;
                    case FormKind.CHOICE: type = Singularity.Pdf.FieldType.COMBO; break;
                    default: type = Singularity.Pdf.FieldType.PUSHBUTTON; break;
                }
                string[] options = {};
                foreach (string o in f.options.split (",")) if (o.strip () != "") options += o.strip ();
                int flags = (f.required ? 2 : 0) | (f.kind == FormKind.TEXT && f.multiline ? (1 << 12) : 0);
                var info = Singularity.Pdf.Forms.create_field (doc, pl.pdf_page, type, name, Singularity.Pdf.Rect.of (x1, y1, x2, y2), options, f.tooltip, flags);
                if (f.kind == FormKind.BUTTON && info.widgets.size > 0) {
                    var w = info.widgets[0].dict;
                    w.remove ("MK");
                    w.set ("F", Singularity.Pdf.Obj.integer (4));
                    var bs = Singularity.Pdf.Obj.dictionary ();
                    bs.set ("W", Singularity.Pdf.Obj.integer (0));
                    w.set ("BS", bs);
                    var act = action_for (doc, pub, place, f.action);
                    if (act != null) w.set ("A", act);
                }
            }
            var so = new Singularity.Pdf.SaveOptions ();
            so.mode = Singularity.Pdf.SaveMode.FULL;
            string tmp = path + ".fin";
            doc.save_to_file (tmp, so);
            FileUtils.rename (tmp, path);
        }

        private static void wrap_document (Singularity.Pdf.Document doc, Singularity.Pdf.Obj cat) {
            var root = doc.resolve (cat.get ("StructTreeRoot"));
            if (root == null || !root.is_dict ()) return;
            var kids = root.get ("K");
            if (kids == null) return;
            var arr = doc.resolve (kids);
            if (arr.is_dict () && doc.lookup (arr, "S").is_name ("Document")) return;
            var elem = Singularity.Pdf.Obj.dictionary ();
            elem.set ("Type", Singularity.Pdf.Obj.name_obj ("StructElem"));
            elem.set ("S", Singularity.Pdf.Obj.name_obj ("Document"));
            elem.set ("P", cat.get ("StructTreeRoot"));
            elem.set ("K", kids);
            var elem_ref = doc.add_ref (elem);
            if (arr.is_array ()) {
                for (int i = 0; i < arr.length; i++) {
                    var k = doc.resolve (arr.at (i));
                    if (k.is_dict ()) k.set ("P", elem_ref);
                }
            } else if (arr.is_dict ()) {
                arr.set ("P", elem_ref);
            }
            root.set ("K", elem_ref);
        }

        private static Singularity.Pdf.Obj? action_for (Singularity.Pdf.Document doc, Publication pub, Gee.HashMap<int, Placement> place, string action) {
            if (action == "") return null;
            var a = Singularity.Pdf.Obj.dictionary ();
            a.set ("Type", Singularity.Pdf.Obj.name_obj ("Action"));
            if (action.has_prefix ("page:")) {
                int pg = int.parse (action.substring (5)) - 1;
                if (!place.has_key (pg)) return null;
                a.set ("S", Singularity.Pdf.Obj.name_obj ("GoTo"));
                var dest = Singularity.Pdf.Obj.array ();
                dest.add (doc.page_refs ()[place[pg].pdf_page]);
                dest.add (Singularity.Pdf.Obj.name_obj ("Fit"));
                a.set ("D", dest);
                return a;
            }
            string named = "";
            switch (action) {
                case "next": named = "NextPage"; break;
                case "previous": named = "PrevPage"; break;
                case "first": named = "FirstPage"; break;
                case "last": named = "LastPage"; break;
                case "print": named = "Print"; break;
                default: break;
            }
            if (named != "") {
                a.set ("S", Singularity.Pdf.Obj.name_obj ("Named"));
                a.set ("N", Singularity.Pdf.Obj.name_obj (named));
                return a;
            }
            a.set ("S", Singularity.Pdf.Obj.name_obj ("URI"));
            a.set ("URI", Singularity.Pdf.Obj.str (action.data));
            return a;
        }
    }
}
