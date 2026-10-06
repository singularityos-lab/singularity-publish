namespace Singularity.Apps.Publish {

    public class DataTable {
        public Gee.ArrayList<string> fields = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Gee.ArrayList<string>> records = new Gee.ArrayList<Gee.ArrayList<string>> ();
    }

    public class Csv {
        public static unichar detect_delimiter (string text) {
            string first = text.split ("\n")[0];
            int commas = 0, semis = 0, tabs = 0;
            bool quoted = false;
            unichar c;
            int i = 0;
            while (first.get_next_char (ref i, out c)) {
                if (c == '"') quoted = !quoted;
                if (quoted) continue;
                if (c == ',') commas++;
                else if (c == ';') semis++;
                else if (c == '\t') tabs++;
            }
            if (tabs > commas && tabs > semis) return '\t';
            if (semis > commas) return ';';
            return ',';
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> parse_rows (string input, unichar delim = 0) {
            string text = input;
            if (text.has_prefix ("\xef\xbb\xbf")) text = text.substring (3);
            if (delim == 0) delim = detect_delimiter (text);
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var row = new Gee.ArrayList<string> ();
            var field = new StringBuilder ();
            bool quoted = false;
            bool field_started = false;
            unichar c;
            int i = 0;
            while (text.get_next_char (ref i, out c)) {
                if (quoted) {
                    if (c == '"') {
                        if (i < text.length && text[i] == '"') {
                            field.append_c ('"');
                            i++;
                        } else {
                            quoted = false;
                        }
                    } else {
                        field.append_unichar (c);
                    }
                    continue;
                }
                if (c == '"' && field.len == 0) {
                    quoted = true;
                    field_started = true;
                } else if (c == delim) {
                    row.add (field.str);
                    field.truncate ();
                    field_started = true;
                } else if (c == '\n' || c == '\r') {
                    if (c == '\r' && i < text.length && text[i] == '\n') i++;
                    row.add (field.str);
                    field.truncate ();
                    if (!(row.size == 1 && row[0] == "" && !field_started)) rows.add (row);
                    row = new Gee.ArrayList<string> ();
                    field_started = false;
                } else {
                    field.append_unichar (c);
                    field_started = true;
                }
            }
            if (field.len > 0 || field_started || row.size > 0) {
                row.add (field.str);
                if (!(row.size == 1 && row[0] == "")) rows.add (row);
            }
            return rows;
        }

        public static DataTable parse (string text, bool header = true) {
            var t = new DataTable ();
            var rows = parse_rows (text);
            if (rows.size == 0) return t;
            int width = 0;
            foreach (var r in rows) width = int.max (width, r.size);
            int start = 0;
            if (header) {
                var h = rows[0];
                for (int i = 0; i < width; i++) {
                    string name = i < h.size ? h[i].strip () : "";
                    if (name == "") name = _("Field %d").printf (i + 1);
                    string unique = name;
                    int k = 2;
                    while (t.fields.contains (unique)) unique = "%s %d".printf (name, k++);
                    t.fields.add (unique);
                }
                start = 1;
            } else {
                for (int i = 0; i < width; i++) t.fields.add (_("Field %d").printf (i + 1));
            }
            for (int r = start; r < rows.size; r++) {
                var rec = new Gee.ArrayList<string> ();
                for (int i = 0; i < width; i++) rec.add (i < rows[r].size ? rows[r][i] : "");
                t.records.add (rec);
            }
            return t;
        }

        public static string escape (string v, unichar delim = ',') {
            if (v.index_of_char (delim) >= 0 || v.contains ("\"") || v.contains ("\n") || v.contains ("\r")) return "\"" + v.replace ("\"", "\"\"") + "\"";
            return v;
        }
    }

    public class VCardReader {
        public static string[] field_names () {
            return { _("Full Name"), _("First Name"), _("Last Name"), _("Organization"), _("Job Title"), _("Email"), _("Phone"), _("Street"), _("City"), _("Region"), _("Postal Code"), _("Country"), _("Address"), _("Website"), _("Photo") };
        }

        private static string unescape (string v) {
            return v.replace ("\\n", "\n").replace ("\\N", "\n").replace ("\\,", ",").replace ("\\;", ";").replace ("\\\\", "\\");
        }

        private static string[] split_components (string v) {
            var parts = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            for (int i = 0; i < v.length; i++) {
                char c = v[i];
                if (c == '\\' && i + 1 < v.length) {
                    sb.append_c (c);
                    sb.append_c (v[i + 1]);
                    i++;
                    continue;
                }
                if (c == ';') {
                    parts.add (unescape (sb.str));
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            parts.add (unescape (sb.str));
            return parts.to_array ();
        }

        public static void append_records (string text, DataTable t, string photo_dir = "") {
            string unfolded = text.replace ("\r\n", "\n").replace ("\n ", "").replace ("\n\t", "");
            Gee.ArrayList<string>? rec = null;
            foreach (string raw in unfolded.split ("\n")) {
                string line = raw.strip ();
                if (line.up () == "BEGIN:VCARD") {
                    rec = new Gee.ArrayList<string> ();
                    for (int i = 0; i < t.fields.size; i++) rec.add ("");
                    continue;
                }
                if (rec == null) continue;
                if (line.up () == "END:VCARD") {
                    if (rec[0] == "") rec[0] = (rec[1] + " " + rec[2]).strip ();
                    if (rec[0] == "") rec[0] = rec[3];
                    t.records.add (rec);
                    rec = null;
                    continue;
                }
                int colon = line.index_of (":");
                if (colon <= 0) continue;
                string head = line.substring (0, colon);
                string value = line.substring (colon + 1);
                string[] hp = head.split (";");
                string name = hp[0].up ();
                int dot = name.index_of (".");
                if (dot >= 0) name = name.substring (dot + 1);
                switch (name) {
                    case "FN":
                        rec[0] = unescape (value);
                        break;
                    case "N":
                        var c = split_components (value);
                        if (c.length > 0) rec[2] = c[0];
                        if (c.length > 1) rec[1] = c[1];
                        break;
                    case "ORG":
                        rec[3] = split_components (value)[0];
                        break;
                    case "TITLE":
                        rec[4] = unescape (value);
                        break;
                    case "EMAIL":
                        if (rec[5] == "") rec[5] = unescape (value);
                        break;
                    case "TEL":
                        if (rec[6] == "") rec[6] = unescape (value).replace ("tel:", "");
                        break;
                    case "ADR":
                        if (rec[7] != "") break;
                        var a = split_components (value);
                        if (a.length > 2) rec[7] = a[2];
                        if (a.length > 3) rec[8] = a[3];
                        if (a.length > 4) rec[9] = a[4];
                        if (a.length > 5) rec[10] = a[5];
                        if (a.length > 6) rec[11] = a[6];
                        var sb = new StringBuilder ();
                        if (rec[7] != "") sb.append (rec[7]);
                        string line2 = "%s %s %s".printf (rec[10], rec[8], rec[9]).strip ();
                        if (line2 != "") {
                            if (sb.len > 0) sb.append ("\n");
                            sb.append (line2);
                        }
                        if (rec[11] != "") {
                            if (sb.len > 0) sb.append ("\n");
                            sb.append (rec[11]);
                        }
                        rec[12] = sb.str;
                        break;
                    case "URL":
                        if (rec[13] == "") rec[13] = unescape (value);
                        break;
                    case "PHOTO":
                        if (rec[14] == "" && photo_dir != "") rec[14] = save_photo (head, value, photo_dir, t.records.size);
                        break;
                }
            }
        }

        private static string save_photo (string head, string value, string dir, int index) {
            string v = value;
            if (v.has_prefix ("data:")) {
                int comma = v.index_of (",");
                if (comma < 0) return "";
                v = v.substring (comma + 1);
            } else if (!head.up ().contains ("ENCODING=B") && !head.up ().contains ("BASE64")) {
                return v.has_prefix ("file://") ? v.substring (7) : "";
            }
            var data = Base64.decode (v);
            if (data.length == 0) return "";
            string ext = ImageStore.sniff (data);
            if (ext == "") ext = "jpg";
            DirUtils.create_with_parents (dir, 0700);
            string p = Path.build_filename (dir, "contact-%d.%s".printf (index + 1, ext));
            try {
                FileUtils.set_data (p, data);
            } catch (Error e) {
                return "";
            }
            return p;
        }

        public static DataTable parse (string text, string photo_dir = "") {
            var t = new DataTable ();
            foreach (string f in field_names ()) t.fields.add (f);
            append_records (text, t, photo_dir);
            return t;
        }

        public static Gee.ArrayList<string> contact_dirs () {
            var l = new Gee.ArrayList<string> ();
            l.add (Path.build_filename (Environment.get_user_data_dir (), "singularity", "contacts"));
            l.add (Path.build_filename (Environment.get_user_cache_dir (), "singularity-contacts"));
            return l;
        }

        private static void scan (string dir, Gee.ArrayList<string> files, int depth) {
            if (depth > 3) return;
            try {
                var d = Dir.open (dir);
                string? n;
                while ((n = d.read_name ()) != null) {
                    string p = Path.build_filename (dir, n);
                    if (FileUtils.test (p, FileTest.IS_DIR)) scan (p, files, depth + 1);
                    else if (n.down ().has_suffix (".vcf") || n.down ().has_suffix (".vcard")) files.add (p);
                }
            } catch (FileError e) {
            }
        }

        public static DataTable load_contacts (Gee.List<string>? dirs = null, string photo_dir = "") {
            var t = new DataTable ();
            foreach (string f in field_names ()) t.fields.add (f);
            var files = new Gee.ArrayList<string> ();
            foreach (string d in (dirs ?? contact_dirs ())) scan (d, files, 0);
            files.sort ();
            var seen = new Gee.HashSet<string> ();
            foreach (string p in files) {
                try {
                    string text;
                    FileUtils.get_contents (p, out text);
                    int before = t.records.size;
                    append_records (text, t, photo_dir);
                    for (int i = t.records.size - 1; i >= before; i--) {
                        string key = t.records[i][0] + "|" + t.records[i][5];
                        if (seen.contains (key)) t.records.remove_at (i);
                        else seen.add (key);
                    }
                } catch (Error e) {
                }
            }
            t.records.sort ((a, b) => a[0].collate (b[0]));
            return t;
        }
    }

    public class Merge {
        public static void set_source (Publication pub, DataTable t, string kind, string path) {
            pub.merge.fields.clear ();
            pub.merge.fields.add_all (t.fields);
            pub.merge.records.clear ();
            pub.merge.records.add_all (t.records);
            pub.merge.source_kind = kind;
            pub.merge.source_path = path;
            pub.merge.preview = t.records.size > 0 ? 0 : -1;
        }

        public static string image_path (Publication pub, string value) {
            if (value == "" || Path.is_absolute (value) || value.has_prefix ("file:")) return value.has_prefix ("file://") ? value.substring (7) : value;
            if (pub.merge.source_path != "") {
                string p = Path.build_filename (Path.get_dirname (pub.merge.source_path), value);
                if (FileUtils.test (p, FileTest.EXISTS) || pub.base_dir == "") return p;
            }
            return pub.base_dir != "" ? Path.build_filename (pub.base_dir, value) : value;
        }

        public static void clear_source (Publication pub) {
            pub.merge = new MergeSettings ();
        }

        public static Gee.ArrayList<string> used_fields (Publication pub) {
            var set = new Gee.ArrayList<string> ();
            foreach (var s in pub.stories.values) foreach (string f in s.fields ()) {
                if (Fields.is_merge (f) && !set.contains (Fields.merge_name (f))) set.add (Fields.merge_name (f));
            }
            pub.walk ((r) => {
                var im = r.item as ImageFrame;
                if (im != null && im.merge_field != "" && !set.contains (im.merge_field)) set.add (im.merge_field);
                var tb = r.item as TableItem;
                if (tb != null) foreach (var row in tb.cells) foreach (var c in row) foreach (string f in c.story.fields ()) {
                    if (Fields.is_merge (f) && !set.contains (Fields.merge_name (f))) set.add (Fields.merge_name (f));
                }
                return true;
            });
            return set;
        }

        public static bool image_field (Publication pub, string field) {
            if (field.has_prefix ("@")) return true;
            int fi = pub.merge.fields.index_of (field);
            if (fi < 0) return false;
            int seen = 0, images = 0;
            foreach (var r in pub.merge.records) {
                if (fi >= r.size || r[fi].strip () == "") continue;
                seen++;
                string v = r[fi].strip ().down ();
                foreach (string ext in new string[] { ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".gif", ".webp", ".bmp", ".svg", ".psd", ".pdf" }) {
                    if (v.has_suffix (ext)) {
                        images++;
                        break;
                    }
                }
                if (seen >= 20) break;
            }
            return seen > 0 && images * 2 > seen;
        }

        public static Gee.ArrayList<string> image_fields (Publication pub) {
            var list = new Gee.ArrayList<string> ();
            foreach (string f in pub.merge.fields) if (image_field (pub, f)) list.add (f);
            return list;
        }

        public static bool shows (Publication pub, Item it, int record) {
            if (it.show_when == null || record < 0) return true;
            return it.show_when.matches (pub.merge.value (record, it.show_when.field));
        }

        public static void resolve_story (Story s, Publication pub, int record) {
            var dead = new Gee.ArrayList<Paragraph> ();
            foreach (var p in s.paras) {
                bool had_field = false, has_content = false;
                foreach (var r in p.runs) {
                    if (r.field != "" && Fields.is_merge (r.field)) {
                        had_field = true;
                        r.text = pub.merge.value (record, Fields.merge_name (r.field)).replace ("\r\n", "\u2028").replace ("\n", "\u2028");
                        r.field = "";
                        if (r.text.strip () != "") has_content = true;
                    } else if (r.field != "" || r.anchor != null || r.text.strip () != "") {
                        has_content = true;
                    }
                }
                if (pub.merge.remove_blank_lines && had_field && !has_content) dead.add (p);
                p.normalize ();
            }
            foreach (var p in dead) if (s.paras.size > 1) s.paras.remove (p);
        }

        private static bool resolve_item (Item it, Publication src, Publication dst, int record) {
            if (!shows (src, it, record)) return false;
            it.show_when = null;
            var t = it as TextFrame;
            if (t != null && dst.stories.has_key (t.story)) resolve_story (dst.stories[t.story], src, record);
            var im = it as ImageFrame;
            if (im != null && im.merge_field != "") {
                string v = image_path (src, src.merge.value (record, im.merge_field));
                bool found = v != "" && FileUtils.test (v, FileTest.IS_REGULAR);
                if (v != "") {
                    im.link = v;
                    im.media = "";
                    im.link_stamp = "";
                }
                if (src.merge.image_fit >= 0) im.fit = (FitMode) src.merge.image_fit;
                im.merge_field = "";
                if (!found && src.merge.hide_missing_images) return false;
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) resolve_story (c.story, src, record);
            var g = it as GroupItem;
            if (g != null) {
                var drop = new Gee.ArrayList<Item> ();
                foreach (var c in g.children) if (!resolve_item (c, src, dst, record)) drop.add (c);
                foreach (var c in drop) g.children.remove (c);
            }
            return true;
        }

        private static Gee.ArrayList<int> records_in (Publication pub, int from, int to) {
            if (from < 0 && to < 0) return pub.merge.selected_records ();
            var l = new Gee.ArrayList<int> ();
            int a = from < 0 ? 0 : from, b = to < 0 ? pub.merge.records.size - 1 : int.min (to, pub.merge.records.size - 1);
            for (int i = a; i <= b; i++) l.add (i);
            return l;
        }

        public static Publication expand (Publication pub, int from = -1, int to = -1) {
            if (pub.merge.catalogue) return expand_catalogue (pub, from, to);
            var outp = pub.clone ();
            outp.pages.clear ();
            outp.stories.clear ();
            outp.sections.clear ();
            outp.sections.add (new Section (0));
            foreach (var m in outp.masters) collect_master_stories (pub, outp, m);
            var recs = records_in (pub, from, to);
            foreach (int rec in recs) {
                var map = new Gee.HashMap<int, int> ();
                for (int pi = 0; pi < pub.pages.size; pi++) {
                    var src = pub.pages[pi];
                    var pg = outp.add_page (-1, src.master);
                    pg.hide_master = src.hide_master;
                    pg.overridden.add_all (src.overridden);
                    foreach (var g in src.guides) pg.guides.add (g.clone ());
                    foreach (var it in src.items) {
                        var c = it.clone ();
                        copy_with_stories (pub, outp, c, map);
                        pg.items.add (c);
                    }
                    var gone = new Gee.ArrayList<Item> ();
                    foreach (var it in pg.items) if (!resolve_item (it, pub, outp, rec)) gone.add (it);
                    foreach (var it in gone) pg.items.remove (it);
                }
            }
            outp.merge = new MergeSettings ();
            outp.prune_stories ();
            return outp;
        }

        private static void collect_master_stories (Publication src, Publication dst, MasterPage m) {
            var all = new Gee.ArrayList<Item> ();
            all.add_all (m.items);
            all.add_all (m.left_items);
            foreach (var it in all) collect_stories (src, dst, it);
        }

        private static void collect_stories (Publication src, Publication dst, Item it) {
            var t = it as TextFrame;
            if (t != null && src.stories.has_key (t.story)) dst.stories[t.story] = src.stories[t.story].clone ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) collect_stories (src, dst, c);
        }

        private static void copy_with_stories (Publication src, Publication dst, Item it, Gee.HashMap<int, int> story_map) {
            int old_id = it.id;
            it.id = dst.next_id ();
            var t = it as TextFrame;
            if (t != null) {
                int old = t.story;
                if (!story_map.has_key (old)) {
                    var s = src.stories.has_key (old) ? src.stories[old].clone () : new Story (0);
                    s.id = dst.next_id ();
                    s.frames.clear ();
                    dst.stories[s.id] = s;
                    story_map[old] = s.id;
                    if (src.stories.has_key (old)) s.frames.add_all (src.stories[old].frames);
                }
                t.story = story_map[old];
                var st = dst.stories[t.story];
                int idx = st.frames.index_of (old_id);
                if (idx >= 0) st.frames[idx] = t.id;
                else st.frames.add (t.id);
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) c.story.id = dst.next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) copy_with_stories (src, dst, c, story_map);
        }

        public static Publication expand_catalogue (Publication pub, int from = -1, int to = -1) {
            var outp = pub.clone ();
            var ms = pub.merge;
            outp.merge = new MergeSettings ();
            if (pub.pages.size == 0) return outp;
            var area = ms.area ();
            var template = new Gee.ArrayList<Item> ();
            var rest = new Gee.ArrayList<Item> ();
            foreach (var it in pub.pages[0].items) {
                if (it.bounds ().inside (area)) template.add (it);
                else rest.add (it);
            }
            var recs = records_in (pub, from, to);
            int per = int.max (1, ms.cat_rows * ms.cat_cols);
            int needed = int.max (1, (recs.size + per - 1) / per);
            var first = pub.pages[0];
            outp.pages.clear ();
            outp.stories.clear ();
            foreach (var m in outp.masters) collect_master_stories (pub, outp, m);
            var story_map = new Gee.HashMap<int, int> ();
            for (int p = 0; p < needed; p++) {
                var pg = outp.add_page (-1, first.master);
                pg.hide_master = first.hide_master;
                foreach (var g in first.guides) pg.guides.add (g.clone ());
                foreach (var it in rest) {
                    var c = it.clone ();
                    story_map.clear ();
                    copy_with_stories (pub, outp, c, story_map);
                    pg.items.add (c);
                }
                for (int k = 0; k < per; k++) {
                    int ri = p * per + k;
                    if (ri >= recs.size) break;
                    int row = k / ms.cat_cols, col = k % ms.cat_cols;
                    double dx = col * (ms.cat_w + ms.cat_gap_x), dy = row * (ms.cat_h + ms.cat_gap_y);
                    foreach (var it in template) {
                        var c = it.clone ();
                        story_map.clear ();
                        copy_with_stories (pub, outp, c, story_map);
                        offset (c, dx, dy);
                        if (resolve_item (c, pub, outp, recs[ri])) pg.items.add (c);
                    }
                }
            }
            for (int p = 1; p < pub.pages.size; p++) {
                var src = pub.pages[p];
                var pg = outp.add_page (-1, src.master);
                foreach (var it in src.items) {
                    var c = it.clone ();
                    story_map.clear ();
                    copy_with_stories (pub, outp, c, story_map);
                    pg.items.add (c);
                }
            }
            outp.prune_stories ();
            return outp;
        }

        private static void offset (Item it, double dx, double dy) {
            var g = it as GroupItem;
            if (g != null) {
                g.move_by (dx, dy);
                return;
            }
            it.x += dx;
            it.y += dy;
        }
    }
}
